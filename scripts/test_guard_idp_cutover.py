import contextlib
import io
import json
import os
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


class ReleasePolicyTests(unittest.TestCase):
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
        for line in result.stdout.splitlines():
            event = json.loads(line)
            if event.get("type") == "test_plan":
                resources.extend(event["test_plan"].get("resource_changes", []))
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
