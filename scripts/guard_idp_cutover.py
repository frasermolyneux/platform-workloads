"""Temporary, fail-closed Production deployment policy for the IDP cutover."""

import argparse
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
ROLE_ID = "4633458b-17de-408a-b874-0445c86b69e6"
COMPUTED_FIELDS = {
    "id", "name", "role_definition_id", "condition_version", "skip_service_principal_aad_check",
}


class PolicyError(Exception):
    pass


def require(condition):
    if not condition:
        raise PolicyError("Saved plan rejected by the IDP cutover release policy.")


def validate_plan(plan):
    require(isinstance(plan, dict))
    require(plan.get("format_version") == "1.2")
    require(plan.get("terraform_version") == "1.17.0")
    require(plan.get("errored") is False and plan.get("complete") is True)
    require(isinstance(plan.get("applyable"), bool))
    require(not plan.get("resource_drift"))
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
        require("previous_address" not in resource)
        change = resource.get("change", {})
        require("importing" not in change)
        actions = change.get("actions")
        if resource.get("mode") == "data":
            require(actions in (["no-op"], ["read"]))
            continue
        require(resource.get("mode") == "managed")
        if actions == ["no-op"]:
            continue
        require(resource.get("address") == ADDRESS)
        require(resource.get("type") == "azurerm_role_assignment")
        require(resource.get("provider_name") == "registry.terraform.io/hashicorp/azurerm")
        require(actions == ["create"] and change.get("before") is None)
        after = change.get("after", {})
        unknown = change.get("after_unknown", {})
        require(isinstance(after, dict) and isinstance(unknown, dict))
        require(all(key in COMPUTED_FIELDS and value is True for key, value in unknown.items() if value))
        for key, value in {
            "principal_id": PRINCIPAL,
            "scope": SCOPE,
            "role_definition_name": "Key Vault Secrets User",
            "principal_type": "ServicePrincipal",
        }.items():
            require(after.get(key) == value and not unknown.get(key))
        for key in ("condition", "delegated_managed_identity_resource_id"):
            require(after.get(key) is None and not unknown.get(key))
        require(after.get("condition_version") is None)
        role_id = after.get("role_definition_id")
        require(role_id is None or role_id.lower() == (
            f"/subscriptions/7760848c-794d-4a19-8cb2-52f71a21ac2b"
            f"/providers/Microsoft.Authorization/roleDefinitions/{ROLE_ID}"
        ).lower())
        creates += 1
    require(creates <= 1)
    outputs = plan.get("output_changes", {})
    require(isinstance(outputs, dict))
    require(all(
        change.get("actions") == ["no-op"] and not change.get("after_unknown")
        for change in outputs.values()
    ))
    require(creates == 0 or plan["applyable"])
    return creates


def command(args, output, accepted=(0,)):
    with output.open("wb") as stream:
        result = subprocess.run(args, stdout=stream, stderr=subprocess.STDOUT, check=False)
    require(result.returncode in accepted)
    return result.returncode


def deploy(root, plan_only=False, retirement_preflight=False):
    require(not any(key.startswith("TF_CLI_ARGS") for key in os.environ))
    require(not any(key.startswith("TF_LOG") for key in os.environ))
    require(os.environ.get("TF_WORKSPACE", "default") == "default")
    root = root.resolve()
    require((root / ".terraform-version").read_text().strip() == "1.17.0")
    terraform = ["terraform", f"-chdir={root}"]
    # All Terraform output, including provider errors, stays on the private runner.
    with tempfile.TemporaryDirectory(prefix="idp-cutover-") as directory:
        private = Path(directory)
        private.chmod(0o700)
        log = private / "command.log"
        command(terraform + ["version", "-json"], log)
        require(json.loads(log.read_text())["terraform_version"] == "1.17.0")
        command(terraform + [
            "init", "-input=false", "-lockfile=readonly",
            "-backend-config=backends/prd.backend.hcl",
        ], log)
        command(terraform + ["validate"], log)
        saved = private / "release.tfplan"
        command(terraform + [
            "plan", "-input=false", "-lock=true", "-lock-timeout=5m",
            "-refresh=true", "-detailed-exitcode", "-var-file=tfvars/prd.tfvars",
            f"-out={saved}",
        ], log, accepted=(0, 2))
        digest = hashlib.sha256(saved.read_bytes()).digest()
        document = private / "plan.json"
        command(terraform + ["show", "-json", str(saved)], document)
        creates = validate_plan(json.loads(document.read_text()))
        require(not retirement_preflight or creates == 0)
        require(hashlib.sha256(saved.read_bytes()).digest() == digest)
        print(f"IDP cutover policy accepted: {creates} approved create(s); no other changes.")
        if retirement_preflight:
            print("Retirement preflight accepted an empty refreshed plan; no apply or policy retirement performed.")
        elif plan_only:
            print("Plan-only check: no apply; private plan deleted when this check exits.")
        elif creates:
            command(terraform + [
                "apply", "-input=false", "-lock=true", "-lock-timeout=5m", str(saved),
            ], log)
            print("Approved saved plan applied successfully.")
        else:
            print("Empty repeat plan: no apply needed.")


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
    except (PolicyError, OSError, ValueError, KeyError, TypeError, AttributeError):
        # Never echo exception text: Terraform/provider diagnostics can contain secrets.
        print(
            "Production deployment blocked or failed. The IDP cutover release restriction remains active; "
            "see docs/idp-collector-cutover.md for reviewed update/retirement. "
            "Private plan policy/execution did not succeed."
        )
        raise SystemExit(1)
