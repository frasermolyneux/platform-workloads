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
DIAGNOSTIC_ADDRESSES = frozenset("""
time_rotating.rotate random_id.environment_id random_id.workload_id
github_repository.workload github_repository_ruleset.workload github_issue_label.workload
github_repository_environment.workload github_repository_environment.nuget
github_actions_environment_variable.nuget_user github_actions_environment_variable.client_id
github_actions_environment_variable.subscription_id github_actions_environment_variable.tenant_id
github_actions_variable.repository_analysis github_actions_variable.repository_standards
github_actions_secret.github_app_pem github_actions_environment_secret.cloudflare_token
azuread_application.workload azuread_service_principal.workload
azuread_application.status_monitoring_reader azuread_service_principal.status_monitoring_reader
azuread_application.status_service azuread_service_principal.status_service
azuread_application.maps_service azuread_service_principal.maps_service
azuread_application_federated_identity_credential.github_workload
azuread_application_federated_identity_credential.github_workload_immutable
azapi_resource.workload_resource_group azurerm_resource_group.rg
azurerm_resource_group.workload_terraform azurerm_storage_account.workload
azurerm_storage_container.workload azurerm_storage_container.workload_tfplan
azurerm_storage_management_policy.workload_tfplan
azurerm_role_assignment.workload azurerm_role_assignment.idp_cost_reader
azurerm_role_assignment.idp_collector_github_app_reader
azurerm_key_vault.kv azurerm_key_vault_secret.github_app_pem cloudflare_api_token.workload
azuread_administrative_unit_role_member.workload
azuread_administrative_unit_role_member.workload_deploy_script
azuread_administrative_unit.platform azuread_app_role_assignment.status_operator
azuread_app_role_assignment.status_secure_webhook_sender
azuread_app_role_assignment.status_traffic_operator azuread_app_role_assignment.workload_graph_api
azuread_app_role_assignment.workload_graph_api_deploy_script
azuread_application_federated_identity_credential.poc
azuread_application_identifier_uri.maps_service azuread_application_identifier_uri.status_service
azuread_application.poc azuread_directory_role_assignment.workload
azuread_directory_role_assignment.workload_deploy_script azuread_directory_role.builtin
azuread_service_principal_delegated_permission_grant.status_operator
azuread_service_principal.microsoft_graph azuread_service_principal.poc
azurerm_role_assignment.deploy_principal_kv_role_assignment
azurerm_role_assignment.poc_keyvault_administrator azurerm_role_assignment.poc_owner
azurerm_role_assignment.poc_storage_blob_data_owner azurerm_role_assignment.status_monitoring_reader
azurerm_role_assignment.workload_deploy_script azurerm_role_assignment.workload_managed_identity_operator
azurerm_role_assignment.workload_platform_workloads_backend_reader
azurerm_role_assignment.workload_provider_registrator azurerm_role_assignment.workload_rbac_administrator
azurerm_role_assignment.workload_resource_group azurerm_role_assignment.workload_storage_blob_contributor
azurerm_role_assignment.workload_storage_blob_key_operator azurerm_role_assignment.workload_storage_reader
azurerm_role_assignment.workload_terraform_state_reader
azurerm_role_definition.resource_provider_registrator azurerm_role_definition.workload_secret_synchronizer
azurerm_user_assigned_identity.workload_deploy_script
github_actions_environment_secret.workload_deploy_script_identity
github_actions_environment_variable.cloudflare_account_id
github_actions_environment_variable.container_registry_name
github_actions_environment_variable.gcp_project_id github_actions_environment_variable.gcp_service_account
github_actions_environment_variable.gcp_workload_identity_provider
github_actions_environment_variable.status_monitoring_reader_client_id
github_actions_environment_variable.status_monitoring_reader_object_id
github_actions_environment_variable.status_service_client_id
github_actions_environment_variable.status_service_object_id
github_actions_secret.sonar_token github_actions_variable.actions_runner
github_actions_variable.github_app_id github_actions_variable.github_app_installation_id
github_actions_variable.repository_standards_catalog github_actions_variable.runtime_github_app
github_dependabot_secret.sonar_token github_dependabot_secret.workload_deploy_script_identity
random_uuid.maps_service_role random_uuid.resource_provider_registrator
random_uuid.status_service_role random_uuid.status_service_scope random_uuid.workload_secret_synchronizer
terraform_data.actions_runner_contract terraform_data.cost_budget_contract
terraform_data.repository_analysis_contract terraform_data.repository_standards_contract
terraform_data.runtime_github_apps_contract
""".split())
DIAGNOSTIC_FIELDS = frozenset("""
id name display_name description tags location scope principal_id principal_type
role_definition_id role_definition_name condition condition_version
rotation_rfc3339 rfc3339 rotation_days day hour minute month second unix year
visibility topics vulnerability_alerts archived default_branch rules
enforcement bypass_actors etag output body identity owners app_role
client_id object_id tenant_id service_principal_names identifier_uris
value plaintext_value encrypted_value updated_at created_at
""".split())
TOKEN_FIELD_CLASSES = {
    "name": "REQUIRED",
    "policies": "REQUIRED",
    "condition": "OPTIONAL",
    "expires_on": "OPTIONAL",
    "not_before": "OPTIONAL",
    "status": "OPTIONAL_COMPUTED",
    "id": "COMPUTED",
    "issued_on": "COMPUTED",
    "last_used_on": "COMPUTED",
    "modified_on": "COMPUTED",
    "value": "COMPUTED_SENSITIVE",
}


def diagnose_drift(drift, *, managed_changes=False):
    """Classify privately; emit only source allowlist literals and fixed markers."""
    prefix = "IDP_CUTOVER_CHANGE" if managed_changes else "IDP_CUTOVER_DRIFT"
    if not isinstance(drift, list):
        print(f"{prefix} MALFORMED_DRIFT")
        return
    emitted = 0
    for resource in drift:
        if managed_changes and isinstance(resource, dict):
            change = resource.get("change")
            if resource.get("mode") == "data" or (
                isinstance(change, dict) and change.get("actions") == ["no-op"]
            ):
                continue
        if emitted == 20:
            print(f"{prefix} MORE_ENTRIES_REDACTED")
            break
        emitted += 1
        if not isinstance(resource, dict):
            print(f"{prefix} MALFORMED_ENTRY")
            continue
        raw_address = resource.get("address")
        base = raw_address.split("[", 1)[0] if isinstance(raw_address, str) else None
        address = base if base in DIAGNOSTIC_ADDRESSES else "UNKNOWN_ADDRESS"
        instance = "INSTANCE_REDACTED" if isinstance(raw_address, str) and "[" in raw_address else "SINGLETON"
        change = resource.get("change", {})
        if not isinstance(change, dict):
            print(f"{prefix} address={address} instance={instance} MALFORMED_CHANGE")
            continue
        actions = change.get("actions")
        action = {
            ("no-op",): "NO_OP", ("update",): "UPDATE", ("delete",): "DELETE",
            ("create",): "CREATE", ("delete", "create"): "REPLACE",
            ("create", "delete"): "REPLACE", ("read",): "READ",
        }.get(tuple(actions) if isinstance(actions, list) and all(isinstance(item, str) for item in actions) else (), "UNKNOWN_ACTION")
        before, after = change.get("before"), change.get("after")
        # A create/delete has one null side; classify fields without emitting values.
        if (isinstance(before, dict) or before is None) and (isinstance(after, dict) or after is None):
            before, after = before or {}, after or {}
            changed = {
                key for key in before.keys() | after.keys()
                if key not in before or key not in after or before[key] != after[key]
            }
            if managed_changes and isinstance(change.get("after_unknown"), dict):
                changed.update(key for key, value in change["after_unknown"].items() if value)
            fields = {
                key if key in DIAGNOSTIC_FIELDS or (
                    address == "cloudflare_api_token.workload" and key in TOKEN_FIELD_CLASSES
                ) else "UNKNOWN_FIELD"
                for key in changed
            }
        else:
            fields = {"NON_OBJECT_CHANGE"}
        schema = ""
        if address == "cloudflare_api_token.workload":
            schema = " schema=" + (
                ",".join(
                    f"{field}:{TOKEN_FIELD_CLASSES.get(field, 'UNKNOWN_CLASS')}"
                    for field in sorted(fields)
                ) or "NO_TOP_LEVEL_CHANGE"
            )
        print(
            f"{prefix} address={address} instance={instance} action={action} "
            f"fields={','.join(sorted(fields)) or 'NO_TOP_LEVEL_CHANGE'}{schema}"
        )


class PolicyError(Exception):
    def __init__(self, reason="POLICY_REJECTED", stage="POLICY"):
        super().__init__()
        self.reason = reason
        self.stage = stage


def require(condition, reason="POLICY_REJECTED"):
    if not condition:
        raise PolicyError(reason)


def validate_token_usage_drift(plan):
    drift = plan["resource_drift"]
    changes = plan.get("resource_changes")
    require(isinstance(drift, list) and bool(drift) and isinstance(changes, list))
    configured = plan.get("configuration", {}).get("root_module", {}).get("resources", [])
    require(isinstance(configured, list))
    declarations = [
        item for item in configured
        if isinstance(item, dict) and item.get("address") == "cloudflare_api_token.workload"
    ]
    require(len(declarations) == 1 and declarations[0].get("mode") == "managed")
    require("for_each_expression" in declarations[0])
    seen = set()
    for resource in drift:
        require(isinstance(resource, dict))
        address = resource.get("address")
        require(isinstance(address, str) and address.startswith('cloudflare_api_token.workload["'))
        require(address.endswith('"]'))
        index = json.loads(address[len("cloudflare_api_token.workload"):][1:-1])
        require(isinstance(index, str) and bool(index))
        require(address == f"cloudflare_api_token.workload[{json.dumps(index, ensure_ascii=False)}]")
        require(address not in seen)
        seen.add(address)
        matches = [item for item in changes if isinstance(item, dict) and item.get("address") == address]
        require(len(matches) == 1)
        match = matches[0]
        for item in (resource, match):
            require(item.get("mode") == "managed" and item.get("type") == "cloudflare_api_token")
            require(item.get("name") == "workload" and item.get("index") == index)
            require(item.get("provider_name") == "registry.terraform.io/cloudflare/cloudflare")
            require("previous_address" not in item and "deposed" not in item)
            change = item.get("change")
            require(isinstance(change, dict) and "importing" not in change)
            require(set(change) <= {
                "actions", "before", "after", "after_unknown", "before_sensitive", "after_sensitive",
            })
            require(change.get("after_unknown") == {})
        change = resource["change"]
        require(change.get("actions") == ["update"])
        before, after = change.get("before"), change.get("after")
        require(isinstance(before, dict) and isinstance(after, dict))
        require(set(before) == set(after) == set(TOKEN_FIELD_CLASSES))
        require(
            json.dumps({key: value for key, value in before.items() if key != "last_used_on"}, sort_keys=True)
            == json.dumps({key: value for key, value in after.items() if key != "last_used_on"}, sort_keys=True)
        )
        require(before["last_used_on"] != after["last_used_on"])
        require(all(value is None or isinstance(value, str) for value in (
            before["last_used_on"], after["last_used_on"],
        )))
        require(all(isinstance(after[field], str) and bool(after[field]) for field in ("id", "name", "value")))
        require(isinstance(after["policies"], list) and bool(after["policies"]))
        require(after["condition"] is None or isinstance(after["condition"], dict))
        require(after["status"] in ("active", "disabled", "expired"))
        require(all(after[field] is None or isinstance(after[field], str) for field in (
            "expires_on", "not_before", "issued_on", "modified_on",
        )))
        noop = match["change"]
        require(noop.get("actions") == ["no-op"])
        require(
            json.dumps(noop.get("before"), sort_keys=True)
            == json.dumps(noop.get("after"), sort_keys=True)
            == json.dumps(after, sort_keys=True)
        )


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
    if plan.get("resource_drift"):
        try:
            validate_token_usage_drift(plan)
        except (PolicyError, ValueError, KeyError, TypeError, AttributeError, RecursionError):
            try:
                diagnose_drift(plan["resource_drift"])
                diagnose_drift(plan.get("resource_changes", []), managed_changes=True)
            except (ValueError, KeyError, TypeError, AttributeError, RecursionError):
                print("IDP_CUTOVER_DIAGNOSTIC INVALID_SHAPE")
            raise PolicyError("UNEXPECTED_DRIFT") from None
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
            inspected_plan = json.loads(document.read_text())
            creates = validate_plan(inspected_plan)
            require(not retirement_preflight or not inspected_plan.get("resource_drift"), "UNEXPECTED_DRIFT")
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
