"""Temporary, fail-closed Production deployment policy for the IDP cutover."""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


ADDRESS = "azurerm_role_assignment.idp_collector_github_app_reader"
PRINCIPAL = "cecfaca8-1076-4439-8b0e-7da8b82c2600"
SCOPE = (
    "/subscriptions/7760848c-794d-4a19-8cb2-52f71a21ac2b"
    "/resourceGroups/rg-platform-workloads-prd-uksouth-01"
    "/providers/Microsoft.KeyVault/vaults/kv-07959418ca04-uksouth"
    "/secrets/github-app-pem"
)
COMPUTED_FIELDS = {
    "id", "name", "role_definition_id", "condition_version", "skip_service_principal_aad_check",
}


class PolicyError(Exception):
    def __init__(self, reason="POLICY_REJECTED", stage="POLICY"):
        super().__init__()
        self.reason = reason
        self.stage = stage


def require(condition, reason="POLICY_REJECTED"):
    if not condition:
        raise PolicyError(reason)


@contextmanager
def stage(name):
    try:
        yield
    except PolicyError as error:
        error.stage = name
        raise
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        raise PolicyError("INVALID_DATA_OR_IO", name) from None


def validate_plan(plan):
    require(isinstance(plan, dict))
    require(plan.get("format_version") == "1.2")
    require(plan.get("terraform_version") == "1.17.0")
    require(plan.get("errored") is False and plan.get("complete") is True, "PLAN_NOT_COMPLETE")
    require(isinstance(plan.get("applyable"), bool))
    require(not plan.get("resource_drift"), "UNEXPECTED_DRIFT")
    require(not plan.get("deferred_changes"))
    require(not plan.get("action_invocations"))
    require(not plan.get("diagnostics"))
    for check in plan.get("checks", []):
        require(check.get("status") == "pass")
        require(all(item.get("status") == "pass" for item in check.get("instances", [])))

    changes = plan.get("resource_changes", [])
    require(isinstance(changes, list))
    creates = 0
    for resource in changes:
        require("previous_address" not in resource, "MOVE_OR_IMPORT")
        change = resource.get("change", {})
        require("importing" not in change, "MOVE_OR_IMPORT")
        actions = change.get("actions")
        if resource.get("mode") == "data":
            require(actions in (["no-op"], ["read"]))
            continue
        require(resource.get("mode") == "managed")
        if actions == ["no-op"]:
            continue
        require(resource.get("address") == ADDRESS, "UNEXPECTED_MANAGED_CHANGE")
        require(resource.get("type") == "azurerm_role_assignment")
        require(resource.get("provider_name") == "registry.terraform.io/hashicorp/azurerm")
        require(actions == ["create"] and change.get("before") is None)
        after = change.get("after", {})
        unknown = change.get("after_unknown", {})
        require(isinstance(after, dict) and isinstance(unknown, dict))
        require(
            set(unknown) == COMPUTED_FIELDS and all(value is True for value in unknown.values()),
            "GRANT_UNKNOWN_SHAPE",
        )
        require(after == {
            "condition": None,
            "delegated_managed_identity_resource_id": None,
            "description": None,
            "principal_id": PRINCIPAL,
            "scope": SCOPE,
            "role_definition_name": "Key Vault Secrets User",
            "principal_type": "ServicePrincipal",
            "timeouts": None,
        }, "GRANT_AFTER_SHAPE")
        creates += 1
    require(creates <= 1)
    outputs = plan.get("output_changes", {})
    require(isinstance(outputs, dict))
    require(all(
        change.get("actions") == ["no-op"] and not change.get("after_unknown")
        for change in outputs.values()
    ), "OUTPUT_CHANGE")
    require(creates == 0 or plan["applyable"])
    return creates


def command(args, output, accepted=(0,)):
    with output.open("wb") as stream:
        result = subprocess.run(args, stdout=stream, stderr=subprocess.STDOUT, check=False)
    require(result.returncode in accepted, "COMMAND_FAILED")
    return result.returncode


def receipt_outcome(operation, outcome):
    require(operation in ("plan", "apply") and outcome in ("success", "failure"))
    if "GITHUB_OUTPUT" in os.environ:
        with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as output:
            output.write(f"{operation}_outcome={outcome}\n")


def deploy(root, plan_only=False, retirement_preflight=False):
    with stage("PREFLIGHT"):
        require(not any(key.startswith("TF_CLI_ARGS") for key in os.environ), "UNSAFE_ENVIRONMENT")
        require(not any(key.startswith("TF_LOG") for key in os.environ), "UNSAFE_ENVIRONMENT")
        require(os.environ.get("TF_WORKSPACE", "default") == "default", "UNSAFE_WORKSPACE")
        root = root.resolve()
        require((root / ".terraform-version").read_text().strip() == "1.17.0", "CLI_PIN_MISMATCH")
    terraform = ["terraform", f"-chdir={root}"]
    # All Terraform output, including provider errors, stays on the private runner.
    with tempfile.TemporaryDirectory(prefix="idp-cutover-") as directory:
        private = Path(directory)
        private.chmod(0o700)
        log = private / "command.log"
        with stage("VERSION"):
            command(terraform + ["version", "-json"], log)
            require(json.loads(log.read_text())["terraform_version"] == "1.17.0", "CLI_PIN_MISMATCH")
        with stage("INIT"):
            command(terraform + [
                "init", "-input=false", "-lockfile=readonly",
                "-backend-config=backends/prd.backend.hcl",
            ], log)
        with stage("VALIDATE"):
            command(terraform + ["validate"], log)
        saved = private / "release.tfplan"
        with stage("PLAN"):
            receipt_outcome("plan", "failure")
            command(terraform + [
                "plan", "-input=false", "-lock=true", "-lock-timeout=5m",
                "-refresh=true", "-detailed-exitcode", "-var-file=tfvars/prd.tfvars",
                f"-out={saved}",
            ], log, accepted=(0, 2))
            receipt_outcome("plan", "success")
            digest = hashlib.sha256(saved.read_bytes()).digest()
        document = private / "plan.json"
        with stage("SHOW"):
            command(terraform + ["show", "-json", str(saved)], document)
        with stage("POLICY"):
            creates = validate_plan(json.loads(document.read_text()))
            require(not retirement_preflight or creates == 0, "RETIREMENT_NOT_EMPTY")
        with stage("INTEGRITY"):
            require(hashlib.sha256(saved.read_bytes()).digest() == digest, "PLAN_DIGEST_CHANGED")
        print(f"IDP cutover policy accepted: {creates} approved create(s); no other changes.")
        if retirement_preflight:
            print("Retirement preflight accepted an empty refreshed plan; no apply or policy retirement performed.")
        elif plan_only:
            print("Plan-only check: no apply; private plan deleted when this check exits.")
        elif creates:
            with stage("APPLY"):
                receipt_outcome("apply", "failure")
                command(terraform + [
                    "apply", "-input=false", "-lock=true", "-lock-timeout=5m", str(saved),
                ], log)
                receipt_outcome("apply", "success")
            print("Approved saved plan applied successfully.")
        else:
            print("Empty repeat plan: no apply needed.")


def report_failure(error):
    # Never echo exception text: Terraform/provider diagnostics can contain secrets.
    allowed_stages = {
        "PREFLIGHT", "VERSION", "INIT", "VALIDATE", "PLAN", "SHOW", "POLICY", "INTEGRITY", "APPLY",
    }
    allowed_reasons = {
        "POLICY_REJECTED", "GRANT_AFTER_SHAPE", "GRANT_UNKNOWN_SHAPE", "COMMAND_FAILED",
        "INVALID_DATA_OR_IO", "UNSAFE_ENVIRONMENT", "UNSAFE_WORKSPACE", "CLI_PIN_MISMATCH",
        "RETIREMENT_NOT_EMPTY", "PLAN_DIGEST_CHANGED", "PLAN_NOT_COMPLETE", "UNEXPECTED_DRIFT",
        "MOVE_OR_IMPORT", "UNEXPECTED_MANAGED_CHANGE", "OUTPUT_CHANGE",
    }
    code_stage = error.stage if isinstance(error, PolicyError) and error.stage in allowed_stages else "RUNNER"
    reason = error.reason if isinstance(error, PolicyError) and error.reason in allowed_reasons else "INTERNAL_FAILURE"
    print(f"IDP_CUTOVER_FAILURE stage={code_stage} reason={reason}")
    print(
        "Production deployment blocked or failed. The IDP cutover release restriction remains active; "
        "see docs/idp-collector-cutover.md for reviewed update/retirement. "
        "Private plan policy/execution did not succeed."
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--retirement-preflight", action="store_true")
    args = parser.parse_args()
    try:
        deploy(
            Path(__file__).resolve().parents[1] / "terraform",
            plan_only=args.plan_only, retirement_preflight=args.retirement_preflight,
        )
    except (PolicyError, OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        report_failure(error)
        raise SystemExit(1)
