import contextlib
import copy
import io
import json
import os
import re
from pathlib import Path
import sys
import tempfile
import unittest
import subprocess
from unittest.mock import patch

import guard_idp_cutover as guard


def plan():
    return {
        "format_version": "1.2", "terraform_version": "1.17.0",
        "complete": True, "errored": False, "applyable": True,
        "resource_changes": [{
            "address": guard.ADDRESS, "mode": "managed", "type": "azurerm_role_assignment",
            "provider_name": "registry.terraform.io/hashicorp/azurerm",
            "change": {
                "actions": ["create"], "before": None,
                "after": {
                    "condition": None, "delegated_managed_identity_resource_id": None,
                    "description": None, "timeouts": None,
                    "principal_id": guard.PRINCIPAL, "scope": guard.SCOPE,
                    "role_definition_name": "Key Vault Secrets User",
                    "principal_type": "ServicePrincipal",
                },
                "after_unknown": {
                    "id": True, "name": True, "role_definition_id": True,
                    "condition_version": True, "skip_service_principal_aad_check": True,
                },
            },
        }],
        "output_changes": {},
    }


def token_usage_plan():
    document = plan()
    before = {
        "id": "test-token-id", "name": "test-token-name", "value": "private-token-fixture",
        "policies": [{"effect": "allow", "permission_groups": [{"id": "test-group"}],
                      "resources": '{"test-account":"*"}'}],
        "condition": None, "expires_on": None, "not_before": None, "status": "active",
        "issued_on": "2026-01-01T00:00:00Z", "modified_on": "2026-01-01T00:00:00Z",
        "last_used_on": None,
    }
    after = before | {"last_used_on": "2026-11-10T00:00:00Z"}
    resource = {
        "address": 'cloudflare_api_token.workload["test-prd-worker"]',
        "mode": "managed", "type": "cloudflare_api_token", "name": "workload",
        "index": "test-prd-worker", "provider_name": "registry.terraform.io/cloudflare/cloudflare",
        "change": {
            "actions": ["update"], "before": before, "after": after, "after_unknown": {},
            "before_sensitive": {"value": True}, "after_sensitive": {"value": True},
        },
    }
    document["resource_drift"] = [resource]
    noop = copy.deepcopy(resource)
    noop["change"].update(actions=["no-op"], before=copy.deepcopy(after))
    document["resource_changes"].append(noop)
    document["configuration"] = {"root_module": {"resources": [{
        "address": "cloudflare_api_token.workload", "mode": "managed",
        "for_each_expression": {"references": ["local.cloudflare_tokens"]},
    }]}}
    return document


class ReleasePolicyTests(unittest.TestCase):
    def test_only_token_usage_refresh_with_exact_noop_can_accompany_grant_or_empty_repeat(self):
        document = token_usage_plan()
        self.assertEqual(guard.validate_plan(document), 1)
        document["resource_changes"].pop(0)
        document["applyable"] = False
        self.assertEqual(guard.validate_plan(document), 0)
        document["resource_drift"][0]["change"]["before"]["last_used_on"] = "2026-11-09T00:00:00Z"
        self.assertEqual(guard.validate_plan(document), 0)

    def test_token_usage_exception_rejects_every_other_field_change(self):
        for field in guard.TOKEN_FIELD_CLASSES.keys() - {"last_used_on"}:
            document = token_usage_plan()
            document["resource_drift"][0]["change"]["before"][field] = "changed-private-fixture"
            with self.subTest(field=field), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(guard.PolicyError) as error:
                    guard.validate_plan(document)
                self.assertEqual(error.exception.reason, "UNEXPECTED_DRIFT")

    def test_token_usage_exception_rejects_identity_shapes_unknowns_and_actions(self):
        cases = []
        for collection in ("resource_drift", "resource_changes"):
            index = 0 if collection == "resource_drift" else 1
            for key, value in (
                ("mode", "data"), ("type", "other"), ("name", "other"),
                ("provider_name", "other"), ("index", "different"),
                ("address", 'cloudflare_api_token.workload["different"]'),
                ("previous_address", "other"), ("deposed", "other"),
            ):
                document = token_usage_plan()
                document[collection][index][key] = value
                cases.append(document)
            for key, value in (
                ("actions", ["create"]), ("actions", ["delete"]), ("actions", ["update"]),
                ("actions", ["delete", "create"]), ("actions", ["create", "delete"]),
                ("actions", ["read"]), ("actions", [{}]),
                ("after_unknown", {"last_used_on": True}), ("after_unknown", None),
                ("after_unknown", {"value": False}), ("importing", {}),
                ("future_field", "private-fixture"), ("before", []), ("after", None),
            ):
                if key == "actions" and value == ["update"] and collection == "resource_drift":
                    continue
                document = token_usage_plan()
                document[collection][index]["change"][key] = value
                cases.append(document)
        for change in (
            lambda doc: doc.pop("configuration"),
            lambda doc: doc["configuration"]["root_module"]["resources"].clear(),
            lambda doc: doc["resource_changes"].pop(),
            lambda doc: doc["resource_changes"].append(copy.deepcopy(doc["resource_changes"][1])),
            lambda doc: doc["resource_drift"].append(copy.deepcopy(doc["resource_drift"][0])),
            lambda doc: doc["resource_drift"].append({"address": "other", "change": {}}),
            lambda doc: doc["resource_drift"][0]["change"]["after"].pop("value"),
            lambda doc: doc["resource_drift"][0]["change"]["before"].pop("id"),
            lambda doc: doc["resource_drift"][0]["change"].pop("after_unknown"),
            lambda doc: doc["resource_changes"][1]["change"].pop("after_unknown"),
            lambda doc: doc["resource_changes"][1]["change"]["after"].update(value="different"),
            lambda doc: doc["resource_changes"][1]["change"]["before"].update(id="different"),
            lambda doc: doc["resource_drift"][0]["change"]["before"].update(last_used_on="2026-11-10T00:00:00Z"),
            lambda doc: doc["resource_drift"][0]["change"]["after"].update(last_used_on=True),
            lambda doc: doc["resource_drift"][0]["change"]["before"].update(future_field=None),
        ):
            document = token_usage_plan()
            change(document)
            cases.append(document)
        for number, document in enumerate(cases):
            with self.subTest(case=number), contextlib.redirect_stdout(io.StringIO()) as console:
                with self.assertRaises(guard.PolicyError) as error:
                    guard.validate_plan(document)
                self.assertEqual(error.exception.reason, "UNEXPECTED_DRIFT")
                self.assertNotIn("private-fixture", console.getvalue())

    def test_token_usage_exception_does_not_relax_other_release_gates(self):
        for change in (
            lambda doc: doc["resource_changes"][0]["change"]["after"].update(principal_id="other"),
            lambda doc: doc["resource_changes"][0]["change"]["after_unknown"].update(extra=True),
            lambda doc: doc["output_changes"].update(other={"actions": ["update"]}),
            lambda doc: doc["resource_changes"].append({
                "mode": "managed", "address": "other", "change": {"actions": ["delete"]},
            }),
        ):
            document = token_usage_plan()
            change(document)
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(guard.PolicyError):
                guard.validate_plan(document)

    def test_token_usage_comparison_does_not_normalize_nested_types(self):
        document = token_usage_plan()
        document["resource_drift"][0]["change"]["before"]["policies"][0]["resources"] = {"test": 1}
        document["resource_drift"][0]["change"]["after"]["policies"][0]["resources"] = {"test": True}
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(guard.PolicyError):
            guard.validate_plan(document)

    def test_diagnostic_address_literals_cover_every_root_managed_declaration(self):
        root = Path(__file__).resolve().parents[1] / "terraform"
        declarations = set()
        for source in root.glob("*.tf"):
            text = source.read_text()
            self.assertNotRegex(text, r'(?m)^\s*module\s+"', "Add reviewed module handling before diagnostics.")
            declarations.update(
                f"{kind}.{name}" for kind, name in re.findall(
                    r'(?m)^\s*resource\s+"([^"]+)"\s+"([^"]+)"', text,
                )
            )
        self.assertEqual(declarations, guard.DIAGNOSTIC_ADDRESSES)

    def test_malformed_drift_shapes_preserve_policy_rejection(self):
        for drift in (
            "sensitive-fixture", {"sensitive-fixture": True}, [None], ["sensitive-fixture"],
            [{"address": "time_rotating.rotate", "change": "sensitive-fixture"}],
            [{"address": ["sensitive-fixture"], "change": {"actions": [{}]}}],
        ):
            with self.subTest(drift=drift), contextlib.redirect_stdout(io.StringIO()) as console:
                with self.assertRaises(guard.PolicyError) as error:
                    guard.validate_plan(plan() | {"resource_drift": drift, "resource_changes": []})
                self.assertEqual(error.exception.reason, "UNEXPECTED_DRIFT")
                self.assertNotIn("sensitive-fixture", console.getvalue())

    def test_drift_diagnostic_only_emits_allowlisted_literals_and_fixed_markers(self):
        drift = [
            {
                "address": 'github_repository.workload["private-sensitive-fixture"]',
                "change": {
                    "actions": ["update"],
                    "before": {"description": "sensitive-before", "untrusted-sensitive-key": 1},
                    "after": {"description": "sensitive-after", "untrusted-sensitive-key": 2},
                },
            },
            {
                "address": "sensitive-unknown-address",
                "change": {"actions": ["sensitive-unknown-action"], "before": None, "after": None},
            },
            {
                "address": "time_rotating.rotate",
                "change": {"actions": ["delete"], "before": {"id": "sensitive"}, "after": None},
            },
        ]
        with contextlib.redirect_stdout(io.StringIO()) as console:
            with self.assertRaises(guard.PolicyError) as error:
                guard.validate_plan(plan() | {"resource_drift": drift, "resource_changes": []})
        self.assertEqual(error.exception.reason, "UNEXPECTED_DRIFT")
        self.assertEqual(console.getvalue().splitlines(), [
            "IDP_CUTOVER_DRIFT address=github_repository.workload instance=INSTANCE_REDACTED action=UPDATE fields=UNKNOWN_FIELD,description",
            "IDP_CUTOVER_DRIFT address=UNKNOWN_ADDRESS instance=SINGLETON action=UNKNOWN_ACTION fields=NO_TOP_LEVEL_CHANGE",
            "IDP_CUTOVER_DRIFT address=time_rotating.rotate instance=SINGLETON action=DELETE fields=id",
        ])
        self.assertNotIn("sensitive", console.getvalue())

    def test_drift_diagnostic_caps_entries_and_never_relaxes_policy(self):
        drift = [{"address": "not-allowed", "change": {"actions": ["update"], "before": {}, "after": {}}}] * 21
        with contextlib.redirect_stdout(io.StringIO()) as console:
            with self.assertRaises(guard.PolicyError):
                guard.validate_plan(plan() | {"resource_drift": drift, "resource_changes": []})
        self.assertEqual(len(console.getvalue().splitlines()), 21)
        self.assertIn("MORE_ENTRIES_REDACTED", console.getvalue())

    def test_all_token_schema_fields_are_classified_without_values_or_nested_names(self):
        fields = dict.fromkeys(guard.TOKEN_FIELD_CLASSES, "sensitive-fixture")
        resource = {
            "address": 'cloudflare_api_token.workload["private-fixture"]',
            "change": {
                "actions": ["update"], "before": dict.fromkeys(fields, None),
                "after": fields | {"policies": [{"secret-map-key": "secret-value"}]},
            },
        }
        with contextlib.redirect_stdout(io.StringIO()) as console:
            guard.diagnose_drift([resource])
        text = console.getvalue()
        for field, classification in guard.TOKEN_FIELD_CLASSES.items():
            self.assertIn(f"{field}:{classification}", text)
        for forbidden in ("sensitive-fixture", "private-fixture", "secret-map-key", "secret-value"):
            self.assertNotIn(forbidden, text)
        self.assertIn("value:COMPUTED_SENSITIVE", text)
        self.assertIn("status:OPTIONAL_COMPUTED", text)

    def test_rejected_plan_also_classifies_non_noop_changes_without_accepting_them(self):
        document = plan() | {"resource_drift": [{"address": "cloudflare_api_token.workload", "change": {
            "actions": ["update"], "before": {"issued_on": None}, "after": {"issued_on": "secret-date"},
        }}]}
        document["resource_changes"] += [
            {"address": "cloudflare_api_token.workload", "mode": "managed", "change": {
                "actions": ["update"], "before": {"policies": "secret-before"},
                "after": {"policies": "secret-after"},
            }},
            {"address": "sensitive-address", "mode": "managed", "change": {
                "actions": ["delete"], "before": {"sensitive-key": "secret"}, "after": None,
            }},
            {"address": "sensitive-noop", "mode": "managed", "change": {"actions": ["no-op"]}},
            {"address": "sensitive-data", "mode": "data", "change": {"actions": ["read"]}},
        ]
        with contextlib.redirect_stdout(io.StringIO()) as console:
            with self.assertRaises(guard.PolicyError) as error:
                guard.validate_plan(document)
        self.assertEqual(error.exception.reason, "UNEXPECTED_DRIFT")
        text = console.getvalue()
        self.assertIn("issued_on:COMPUTED", text)
        self.assertIn("policies:REQUIRED", text)
        self.assertIn("IDP_CUTOVER_CHANGE address=azurerm_role_assignment.idp_collector_github_app_reader", text)
        self.assertIn("IDP_CUTOVER_CHANGE address=UNKNOWN_ADDRESS", text)
        self.assertNotIn("sensitive-", text)
        self.assertNotIn("secret", text)
        self.assertEqual(len(text.splitlines()), 4)

    def test_change_diagnostics_are_bounded_after_skipping_noops_and_data_reads(self):
        changes = [
            {"mode": "managed", "change": {"actions": ["no-op"]}},
            {"mode": "data", "change": {"actions": ["read"]}},
        ] * 30 + [{
            "mode": "managed", "address": 'cloudflare_api_token.workload["private-fixture"]',
            "change": {"actions": ["create"], "before": None, "after": {"name": None},
                       "after_unknown": {"value": True, "private-key": True}},
        }] * 21
        with contextlib.redirect_stdout(io.StringIO()) as console:
            guard.diagnose_drift(changes, managed_changes=True)
        lines = console.getvalue().splitlines()
        self.assertEqual(len(lines), 21)
        self.assertEqual(lines[-1], "IDP_CUTOVER_CHANGE MORE_ENTRIES_REDACTED")
        self.assertIn("value:COMPUTED_SENSITIVE", lines[0])
        self.assertIn("UNKNOWN_FIELD:UNKNOWN_CLASS", lines[0])
        self.assertNotIn("private-", console.getvalue())

    def test_exact_create_and_empty_repeat(self):
        self.assertEqual(guard.validate_plan(plan()), 1)
        empty = plan() | {"resource_changes": [], "applyable": False}
        self.assertEqual(guard.validate_plan(empty), 0)
        empty["resource_changes"] = [{
            "mode": "managed", "change": {"actions": ["no-op"]},
        }, {"mode": "data", "change": {"actions": ["read"]}}]
        empty["output_changes"] = {"existing": {"actions": ["no-op"]}}
        self.assertEqual(guard.validate_plan(empty), 0)

    def test_reject_any_extra_known_field_or_changed_optional_value(self):
        for field, value in [
            ("description", "unexpected"), ("timeouts", {"create": "10m"}),
            ("future_provider_field", None), ("future_provider_field", "unexpected"),
            ("skip_service_principal_aad_check", False), ("name", "unexpected"),
            ("id", "unexpected"), ("condition_version", None),
            ("role_definition_id", "/unexpected"),
        ]:
            document = plan()
            document["resource_changes"][0]["change"]["after"][field] = value
            with self.subTest(field=field), self.assertRaises(guard.PolicyError):
                guard.validate_plan(document)
        document = plan()
        del document["resource_changes"][0]["change"]["after"]["description"]
        with self.assertRaises(guard.PolicyError):
            guard.validate_plan(document)
        for field in guard.COMPUTED_FIELDS:
            for value in (False, None, {}, 1):
                document = plan()
                document["resource_changes"][0]["change"]["after_unknown"][field] = value
                with self.subTest(field=field, value=value), self.assertRaises(guard.PolicyError):
                    guard.validate_plan(document)
        document = plan()
        document["resource_changes"][0]["change"]["after_unknown"]["extra_false"] = False
        with self.assertRaises(guard.PolicyError):
            guard.validate_plan(document)

    def test_reject_plan_status_drift_outputs_and_checks(self):
        for changes in [
            {"complete": False}, {"complete": None}, {"errored": True},
            {"applyable": False}, {"terraform_version": "1.17.1"},
            {"format_version": "2.0"}, {"resource_drift": [{"change": {"actions": ["update"]}}]},
            {"resource_drift": [{"change": {"actions": ["no-op"]}}]},
            {"deferred_changes": [{}]}, {"diagnostics": [{"severity": "error"}]},
            {"action_invocations": [{}]},
            {"checks": [{"status": "unknown"}]}, {"checks": [{"status": "fail"}]},
            {"checks": [{"status": "pass", "instances": [{"status": "fail"}]}]},
            {"output_changes": {"secret": {"actions": ["update"]}}},
            {"output_changes": {"removed": {"actions": ["delete"]}}},
            {"output_changes": {"unknown": {"actions": ["no-op"], "after_unknown": True}}},
        ]:
            with self.subTest(changes=changes), self.assertRaises(guard.PolicyError):
                guard.validate_plan(plan() | changes)

    def test_reject_unapproved_resource_actions_moves_imports_and_duplicates(self):
        for changes in [
            {"address": "azurerm_role_assignment.other"},
            {"previous_address": "azurerm_role_assignment.old"},
            {"provider_name": "registry.terraform.io/other/provider"},
            {"type": "other"}, {"mode": "ephemeral"},
            {"change": {"actions": ["update"]}},
            {"change": {"actions": ["delete", "create"]}},
            {"change": {"actions": ["create", "delete"]}},
            {"change": {"actions": ["delete"]}},
        ]:
            document = plan()
            document["resource_changes"][0].update(changes)
            with self.subTest(changes=changes), self.assertRaises(guard.PolicyError):
                guard.validate_plan(document)
        for field in ("importing",):
            document = plan()
            document["resource_changes"][0]["change"][field] = {"id": "existing"}
            with self.assertRaises(guard.PolicyError):
                guard.validate_plan(document)
        duplicate = plan()
        duplicate["resource_changes"] *= 2
        with self.assertRaises(guard.PolicyError):
            guard.validate_plan(duplicate)
        extra = plan()
        extra["resource_changes"].append({
            "address": "azurerm_consumption_budget_subscription.existing", "mode": "managed",
            "change": {"actions": ["update"]},
        })
        with self.assertRaises(guard.PolicyError):
            guard.validate_plan(extra)

    def test_reject_wrong_or_unknown_grant(self):
        for field, value in [
            ("principal_id", "another-principal"), ("scope", guard.SCOPE.rsplit("/secrets", 1)[0]),
            ("scope", guard.SCOPE + "/version"), ("role_definition_name", "Owner"),
            ("principal_type", "User"), ("role_definition_id", "/roleDefinitions/other"),
            ("condition", "condition"), ("condition_version", "2.0"),
            ("delegated_managed_identity_resource_id", "/identities/other"),
        ]:
            document = plan()
            document["resource_changes"][0]["change"]["after"][field] = value
            with self.subTest(field=field), self.assertRaises(guard.PolicyError):
                guard.validate_plan(document)
        for field in ("principal_id", "scope", "role_definition_name", "principal_type", "condition"):
            document = plan()
            document["resource_changes"][0]["change"]["after_unknown"][field] = True
            with self.subTest(field=field), self.assertRaises(guard.PolicyError):
                guard.validate_plan(document)
        document = plan()
        document["resource_changes"][0]["change"]["after_unknown"]["future_provider_field"] = True
        with self.assertRaises(guard.PolicyError):
            guard.validate_plan(document)

    @unittest.skipUnless(os.environ.get("CUTOVER_TEST_TERRAFORM"), "Pinned Terraform mock-plan integration is opt-in")
    def test_locked_provider_generated_role_plan(self):
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run([
            os.environ["CUTOVER_TEST_TERRAFORM"], f"-chdir={root / 'terraform'}", "test",
            f"-var-file={Path('tfvars') / 'prd.tfvars'}",
            f"-filter={Path('tests') / 'idp-collector-host.tftest.hcl'}",
            "-json", "-verbose",
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        self.assertEqual(result.returncode, 0, "Mock-only Terraform test failed; output withheld.")
        resources = []
        token_schema = None
        for line in result.stdout.splitlines():
            event = json.loads(line)
            if event.get("type") == "test_plan":
                resources.extend(event["test_plan"].get("resource_changes", []))
                token_schema = event["test_plan"]["provider_schemas"][
                    "registry.terraform.io/cloudflare/cloudflare"
                ]["resource_schemas"]["cloudflare_api_token"]["block"]["attributes"]
        self.assertIsNotNone(token_schema)
        expected_classes = {}
        for field, attribute in token_schema.items():
            classification = (
                "REQUIRED" if attribute.get("required") else
                "OPTIONAL_COMPUTED" if attribute.get("optional") and attribute.get("computed") else
                "OPTIONAL" if attribute.get("optional") else "COMPUTED"
            )
            if attribute.get("sensitive"):
                classification += "_SENSITIVE"
            expected_classes[field] = classification
        self.assertEqual(guard.TOKEN_FIELD_CLASSES, expected_classes)
        assignment = next(item for item in resources if item["address"] == guard.ADDRESS)
        assignment["change"]["after"]["principal_id"] = guard.PRINCIPAL
        assignment["change"]["after"]["scope"] = guard.SCOPE
        document = plan() | {"resource_changes": [assignment]}
        self.assertEqual(guard.validate_plan(document), 1)
        assignment["change"]["after_unknown"]["principal_id"] = True
        with self.assertRaises(guard.PolicyError):
            guard.validate_plan(document)

    @unittest.skipUnless(os.environ.get("CUTOVER_TEST_TERRAFORM"), "Pinned Terraform local-plan integration is opt-in")
    def test_real_saved_empty_plan_envelope_without_backend_or_providers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "main.tf").write_text('terraform { required_version = "= 1.17.0" }\n')
            binary = os.environ["CUTOVER_TEST_TERRAFORM"]
            prefix = [binary, f"-chdir={root}"]
            for arguments in (
                ["init", "-backend=false", "-input=false", "-lockfile=readonly"],
                ["plan", "-input=false", "-refresh=true", "-out=empty.tfplan"],
            ):
                result = subprocess.run(
                    prefix + arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
                )
                self.assertEqual(result.returncode, 0, "Local empty-plan test failed; output withheld.")
            result = subprocess.run(
                prefix + ["show", "-json", "empty.tfplan"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(guard.validate_plan(json.loads(result.stdout)), 0)

    def execute(self, document, *, plan_only=False, retirement_preflight=False, fail=None, corrupt=False):
        calls = []
        self.receipts = []

        def fake_command(args, output, accepted=(0,)):
            operation = args[2]
            calls.append(args)
            if fail == operation:
                raise guard.PolicyError("COMMAND_FAILED")
            if operation == "version":
                output.write_text('{"terraform_version":"1.17.0"}')
            elif operation == "plan":
                saved = Path(next(arg[5:] for arg in args if arg.startswith("-out=")))
                saved.write_bytes(b"approved binary")
            elif operation == "show":
                output.write_text(json.dumps(document))
                if corrupt:
                    Path(args[-1]).write_bytes(b"modified binary")
            elif operation == "apply":
                self.assertEqual(Path(args[-1]).read_bytes(), b"approved binary")
            return 0

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".terraform-version").write_text("1.17.0")
            with patch.dict(os.environ, {}, clear=True), \
                    patch.object(guard, "command", side_effect=fake_command), \
                    patch.object(guard, "receipt_outcome", side_effect=lambda *item: self.receipts.append(item)), \
                    contextlib.redirect_stdout(io.StringIO()) as console:
                try:
                    guard.deploy(root, plan_only=plan_only, retirement_preflight=retirement_preflight)
                except guard.PolicyError as error:
                    guard.report_failure(error)
            self.assertNotIn("secret fixture", console.getvalue())
        return calls, console.getvalue()

    def test_runner_full_locked_refresh_then_same_plan_apply(self):
        calls, _ = self.execute(plan())
        self.assertEqual([call[2] for call in calls], ["version", "init", "validate", "plan", "show", "apply"])
        self.assertIn("-lockfile=readonly", calls[1])
        self.assertIn("-refresh=true", calls[3])
        self.assertIn("-lock=true", calls[3])
        self.assertNotIn("-target", " ".join(calls[3]))
        self.assertEqual(calls[4][-1], calls[5][-1])
        self.assertFalse(Path(calls[5][-1]).exists())

    def test_runner_token_usage_drift_applies_only_saved_grant_and_retirement_still_rejects_drift(self):
        calls, console = self.execute(token_usage_plan())
        self.assertIn("Approved saved plan applied successfully.", console)
        self.assertEqual(calls[-1][2], "apply")
        self.assertEqual(calls[-2][-1], calls[-1][-1])
        self.assertFalse(Path(calls[-1][-1]).parent.exists())
        calls, console = self.execute(token_usage_plan(), plan_only=True)
        self.assertNotIn("apply", [call[2] for call in calls])
        self.assertIn("Plan-only check", console)
        document = token_usage_plan()
        document["resource_changes"].pop(0)
        document["applyable"] = False
        calls, console = self.execute(document, retirement_preflight=True)
        self.assertIn("stage=POLICY reason=UNEXPECTED_DRIFT", console)
        self.assertNotIn("apply", [call[2] for call in calls])
        self.assertFalse(Path(calls[-1][-1]).parent.exists())

    def test_runner_never_applies_failed_invalid_or_changed_plan(self):
        invalid = plan() | {"complete": False}
        for document, options in [
            (invalid, {}), (plan(), {"fail": "plan"}), (plan(), {"fail": "init"}),
            (plan(), {"corrupt": True}), (plan(), {"plan_only": True}),
            (plan() | {"resource_changes": [], "applyable": False}, {}),
        ]:
            with self.subTest(options=options):
                calls, _ = self.execute(document, **options)
                self.assertNotIn("apply", [call[2] for call in calls])

    def test_fixed_codes_distinguish_every_command_stage(self):
        for operation in ("version", "init", "validate", "plan", "show", "apply"):
            with self.subTest(operation=operation):
                _, console = self.execute(plan(), fail=operation)
                self.assertIn(f"stage={operation.upper()} reason=COMMAND_FAILED", console)
        for document, options, code in [
            (plan() | {"complete": False}, {}, "stage=POLICY reason=PLAN_NOT_COMPLETE"),
            (plan() | {"resource_drift": [{}]}, {}, "stage=POLICY reason=UNEXPECTED_DRIFT"),
            (plan(), {"corrupt": True}, "stage=INTEGRITY reason=PLAN_DIGEST_CHANGED"),
            (plan(), {"retirement_preflight": True}, "stage=POLICY reason=RETIREMENT_NOT_EMPTY"),
        ]:
            _, console = self.execute(document, **options)
            self.assertIn(code, console)

    def test_runner_drift_output_stays_bounded_and_private_files_are_cleaned(self):
        for drift in (
            [{"address": 'github_repository.workload["secret-fixture"]',
              "change": {"actions": ["update"], "before": {"description": "secret-fixture"},
                         "after": {"description": "different-secret-fixture"}}}],
            [{"address": "secret-fixture", "change": None}],
            "secret-fixture",
        ):
            calls, console = self.execute(plan() | {"resource_drift": drift})
            self.assertIn("stage=POLICY reason=UNEXPECTED_DRIFT", console)
            self.assertNotIn("secret-fixture", console)
            self.assertNotIn("apply", [call[2] for call in calls])
            saved = Path(next(arg[5:] for call in calls for arg in call if arg.startswith("-out=")))
            self.assertFalse(saved.exists())
            self.assertFalse(saved.parent.exists())

    def test_runner_malformed_changes_and_diagnostic_failure_keep_original_rejection(self):
        for changes in (
            "secret-fixture", {"secret-fixture": True}, [None], ["secret-fixture"],
            [{"address": "secret-fixture", "change": "secret-fixture"}],
            [{"change": {"actions": [{}], "before": [], "after": {"secret-fixture": True}}}],
        ):
            with self.subTest(changes=changes):
                calls, console = self.execute(plan() | {
                    "resource_drift": [{}], "resource_changes": changes,
                })
                self.assertIn("stage=POLICY reason=UNEXPECTED_DRIFT", console)
                self.assertNotIn("secret-fixture", console)
                self.assertNotIn("apply", [call[2] for call in calls])
                saved = Path(next(arg[5:] for call in calls for arg in call if arg.startswith("-out=")))
                self.assertFalse(saved.parent.exists())
        with patch.object(guard, "diagnose_drift", side_effect=ValueError("secret-fixture")):
            calls, console = self.execute(plan() | {"resource_drift": [{}]})
        self.assertIn("IDP_CUTOVER_DIAGNOSTIC INVALID_SHAPE", console)
        self.assertIn("stage=POLICY reason=UNEXPECTED_DRIFT", console)
        self.assertNotIn("secret-fixture", console)
        self.assertNotIn("apply", [call[2] for call in calls])
        saved = Path(next(arg[5:] for call in calls for arg in call if arg.startswith("-out=")))
        self.assertFalse(saved.parent.exists())

    def test_error_reporting_never_echoes_arbitrary_exception_or_code_values(self):
        for error in (
            ValueError("sensitive-fixture"), guard.PolicyError("sensitive-fixture", "sensitive-fixture"),
        ):
            with contextlib.redirect_stdout(io.StringIO()) as console:
                guard.report_failure(error)
            self.assertIn("stage=RUNNER reason=INTERNAL_FAILURE", console.getvalue())
            self.assertNotIn("sensitive-fixture", console.getvalue())
        with self.assertRaises(guard.PolicyError) as error:
            with guard.stage("SHOW"):
                raise ValueError("sensitive-fixture")
        self.assertEqual((error.exception.stage, error.exception.reason), ("SHOW", "INVALID_DATA_OR_IO"))
        with self.assertRaises(guard.PolicyError) as error:
            with guard.stage("APPLY"):
                raise OSError("sensitive-fixture")
        self.assertEqual((error.exception.stage, error.exception.reason), ("APPLY", "INVALID_DATA_OR_IO"))

    def test_receipts_describe_only_actual_attempts_and_truthful_outcomes(self):
        cases = [
            ({}, [("plan", "failure"), ("plan", "success"), ("apply", "failure"), ("apply", "success")]),
            ({"fail": "init"}, []),
            ({"fail": "validate"}, []),
            ({"fail": "plan"}, [("plan", "failure")]),
            ({"fail": "show"}, [("plan", "failure"), ("plan", "success")]),
            ({"fail": "apply"}, [("plan", "failure"), ("plan", "success"), ("apply", "failure")]),
            ({"plan_only": True}, [("plan", "failure"), ("plan", "success")]),
        ]
        for options, expected in cases:
            with self.subTest(options=options):
                self.execute(plan(), **options)
                self.assertEqual(self.receipts, expected)
        self.execute(plan() | {"resource_changes": [], "applyable": False})
        self.assertEqual(self.receipts, [("plan", "failure"), ("plan", "success")])
        self.execute(plan() | {"complete": False})
        self.assertEqual(self.receipts, [("plan", "failure"), ("plan", "success")])
        self.execute(plan(), corrupt=True)
        self.assertEqual(self.receipts, [("plan", "failure"), ("plan", "success")])

    def test_receipt_outputs_are_bounded_metadata_only(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "outputs"
            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}):
                guard.receipt_outcome("plan", "failure")
                guard.receipt_outcome("plan", "success")
                guard.receipt_outcome("apply", "failure")
                with self.assertRaises(guard.PolicyError):
                    guard.receipt_outcome("arbitrary", "sensitive-value")
            self.assertEqual(output.read_text(), "plan_outcome=failure\nplan_outcome=success\napply_outcome=failure\n")

    def test_retirement_preflight_requires_empty_plan_and_never_retires_or_applies(self):
        empty = plan() | {"resource_changes": [], "applyable": False}
        calls, console = self.execute(empty, retirement_preflight=True)
        self.assertIn("Retirement preflight accepted an empty refreshed plan", console)
        self.assertNotIn("apply", [call[2] for call in calls])
        for document in (plan(), plan() | {"resource_drift": [{}]}):
            calls, console = self.execute(document, retirement_preflight=True)
            self.assertNotIn("Retirement preflight accepted", console)
            self.assertNotIn("apply", [call[2] for call in calls])

    def test_cli_output_never_goes_to_console(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "private.log"
            with patch.object(guard.subprocess, "run") as run:
                run.return_value.returncode = 1
                with self.assertRaises(guard.PolicyError):
                    guard.command(["terraform", "plan"], output)
                self.assertEqual(run.call_args.kwargs["stderr"], guard.subprocess.STDOUT)
                self.assertEqual(run.call_args.kwargs["stdout"].name, str(output))

    def test_cli_argument_injection_and_wrong_workspace_fail_before_execution(self):
        for environment in (
            {"TF_CLI_ARGS_plan": "-refresh=false"}, {"TF_WORKSPACE": "other"},
            {"TF_LOG": "TRACE"}, {"TF_LOG_PATH": "unsafe.log"},
        ):
            with patch.dict(os.environ, environment, clear=True), \
                    patch.object(guard, "command") as command, \
                    self.assertRaises(guard.PolicyError):
                guard.deploy(Path("."))
            command.assert_not_called()

    def test_all_production_paths_use_private_guard_and_pr_stays_draft_gated(self):
        workflows = Path(__file__).resolve().parents[1] / ".github" / "workflows"
        for name in ("deploy-prd.yml", "pr-verify.yml", "feature-development.yml"):
            text = (workflows / name).read_text()
            self.assertIn("scripts/guard_idp_cutover.py", text)
            self.assertIn('terraform_wrapper: "false"', text)
            self.assertNotIn("actions/terraform-plan", text)
            self.assertNotIn("upload-artifact", text)
            self.assertNotIn("continue-on-error", text)
            self.assertIn("terraform-receipt@027d7e31bb32b734090aaed01b36d74f1d658b61", text)
            self.assertIn("if: always() && steps.guard.outputs.plan_outcome != ''", text)
            self.assertIn("outcome: ${{ steps.guard.outputs.plan_outcome }}", text)
            self.assertIn("context-directory: ${{ steps.toolchain.outputs.directory }}", text)
            if name == "deploy-prd.yml":
                self.assertNotIn("--plan-only", text)
                self.assertIn("if: always() && steps.guard.outputs.apply_outcome != ''", text)
                self.assertIn("outcome: ${{ steps.guard.outputs.apply_outcome }}", text)
            else:
                self.assertIn("scripts/guard_idp_cutover.py --plan-only", text)
                self.assertNotIn("operation: apply", text)
        pr = (workflows / "pr-verify.yml").read_text()
        self.assertIn("terraform-plan-prd:", pr)
        self.assertIn("if: github.event.pull_request.draft == false", pr)

    def test_blocked_cli_explains_deliberate_retirement_without_exposing_diagnostics(self):
        script = Path(guard.__file__).resolve()
        environment = os.environ | {"TF_CLI_ARGS": "sensitive-fixture-must-not-be-echoed"}
        result = subprocess.run(
            [sys.executable, str(script), "--plan-only"],
            env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"release restriction remains active", result.stdout)
        self.assertIn(b"docs/idp-collector-cutover.md", result.stdout)
        self.assertIn(b"stage=PREFLIGHT reason=UNSAFE_ENVIRONMENT", result.stdout)
        self.assertNotIn(b"sensitive-fixture", result.stdout + result.stderr)
        self.assertEqual(result.stderr, b"")


if __name__ == "__main__":
    unittest.main()
