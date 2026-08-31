import base64
import json
import shutil
import unittest
from pathlib import Path

from scripts import copilot_estate_inventory as inventory


OWNER = "example"
SCRATCH = Path("tests/_scratch")


def response(body, status=200, headers=None):
    return {"status": status, "headers": headers or {}, "body": body}


def blob(text):
    return {
        "encoding": "base64",
        "content": base64.b64encode(text.encode("utf-8")).decode("ascii"),
    }


def catalog_record(
    name="repo",
    *,
    inventory_data=None,
    review_enabled=True,
    visibility="public",
):
    github = {
        "description": "fixture",
        "topics": [],
        "visibility": visibility,
        "manage_repository": False,
    }
    if not review_enabled:
        github["repository_policy"] = {
            "copilot_code_review": {
                "enabled": False,
                "exception_reason": "Fixture exception",
            }
        }
    if inventory_data is not None:
        github["inventory"] = inventory_data
    return {"name": name, "github": github, "_path": f"{name}.json"}


def metadata(default_branch="main", **overrides):
    value = {
        "archived": False,
        "disabled": False,
        "default_branch": default_branch,
        "size": 1,
        "visibility": "public",
        "private": False,
    }
    value.update(overrides)
    return value


def tree_entry(path, sha, text):
    return {"path": path, "type": "blob", "sha": sha, "size": len(text.encode())}


def canonical_rule(draft=False, push=False):
    return {
        "type": "copilot_code_review",
        "parameters": {
            "review_draft_pull_requests": draft,
            "review_on_push": push,
        },
    }


def repo_responses(name, files=None, rule=None, metadata_body=None):
    files = files or {"AGENTS.md": "Keep changes focused.\n"}
    entries = []
    responses = {
        f"/repos/{OWNER}/{name}": response(metadata_body or metadata()),
    }
    for index, (path, text) in enumerate(files.items(), 1):
        sha = f"sha{index}"
        entries.append(tree_entry(path, sha, text))
        responses[f"/repos/{OWNER}/{name}/git/blobs/{sha}"] = response(blob(text))
    responses[f"/repos/{OWNER}/{name}/git/trees/main?recursive=1"] = response(
        {"tree": entries, "truncated": False}
    )
    responses[
        f"/repos/{OWNER}/{name}/rulesets?includes_parents=false&per_page=100&page=1"
    ] = response([{"id": 7}])
    responses[f"/repos/{OWNER}/{name}/rulesets/7"] = response(
        {"id": 7, "rules": [rule or canonical_rule()]}
    )
    return responses


def run_records(records, responses):
    transport = inventory.FixtureTransport(responses)
    client = inventory.GitHubClient("secret", transport=transport, retries=0)
    parsed, catalog_findings, duplicates = inventory.load_catalog(
        Path("unused"), records
    )
    repositories = [
        inventory.inspect_repository(record, OWNER, client) for record in parsed
    ]
    report = inventory.build_report(
        parsed,
        catalog_findings,
        duplicates,
        repositories,
        owner=OWNER,
        catalog_root=Path("unused"),
        fixture=None,
        baseline=None,
        client=client,
    )
    return report, transport


class InventoryTests(unittest.TestCase):
    def setUp(self):
        shutil.rmtree(SCRATCH, ignore_errors=True)
        SCRATCH.mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(SCRATCH, ignore_errors=True)

    def test_compliant_repository(self):
        report, _ = run_records(
            [catalog_record()],
            repo_responses(
                "repo",
                {
                    "AGENTS.md": "Keep changes focused.\n",
                    ".github/copilot-instructions.md": "Keep repository guidance portable.\n",
                    ".github/instructions/python.instructions.md": (
                        "---\napplyTo: \"**/*.py\"\n---\nUse the standard library.\n"
                    ),
                    "src/app.py": "print('ok')\n",
                },
            ),
        )
        self.assertEqual("pass", report["overall"]["result"])
        self.assertEqual(1, report["totals"]["instruction_files"])
        measurements = report["repositories"][0]["measurements"]
        self.assertGreater(measurements["core"]["combined_bytes"], 0)
        instruction = next(
            item for item in measurements["files"] if item["kind"] == "instruction"
        )
        self.assertEqual(["**/*.py"], instruction["apply_to"])
        self.assertGreater(instruction["lines"], 0)

    def test_empty_repository_is_metadata_only(self):
        record = catalog_record(
            "empty",
            review_enabled=False,
            inventory_data={
                "state": "empty",
                "inspection": "metadata",
                "review_governance": "exempt",
                "reason": "No default branch",
            },
        )
        report, transport = run_records(
            [record],
            {f"/repos/{OWNER}/empty": response(metadata(None, size=0))},
        )
        repo = report["repositories"][0]
        self.assertEqual("empty", repo["classification"])
        self.assertEqual([f"/repos/{OWNER}/empty"], transport.requests)

    def test_archived_repository_is_metadata_only(self):
        report, transport = run_records(
            [catalog_record("archived")],
            {
                f"/repos/{OWNER}/archived": response(
                    metadata("main", archived=True)
                )
            },
        )
        repo = report["repositories"][0]
        self.assertEqual("archived/disabled", repo["classification"])
        self.assertEqual("metadata", repo["inspection"])
        self.assertEqual([f"/repos/{OWNER}/archived"], transport.requests)

    def test_excluded_repository_is_never_queried(self):
        record = catalog_record(
            "excluded",
            review_enabled=False,
            inventory_data={
                "state": "excluded",
                "inspection": "none",
                "review_governance": "exempt",
                "reason": "Excluded fixture",
            },
        )
        report, transport = run_records([record], {})
        self.assertEqual("excluded", report["repositories"][0]["classification"])
        self.assertEqual([], transport.requests)

    def test_decommissioned_repository_is_never_queried(self):
        record = catalog_record(
            "old",
            review_enabled=False,
            inventory_data={
                "state": "decommissioned",
                "inspection": "none",
                "review_governance": "exempt",
                "reason": "Decommissioned fixture",
            },
        )
        report, transport = run_records([record], {})
        self.assertEqual("decommissioned", report["repositories"][0]["classification"])
        self.assertEqual([], transport.requests)

    def test_missing_agents_is_warning(self):
        report, _ = run_records(
            [catalog_record()],
            repo_responses("repo", {"README.md": "# Repo\n"}),
        )
        codes = {item["code"] for item in report["repositories"][0]["findings"]}
        self.assertIn("agents_guidance_missing", codes)
        self.assertEqual(0, report["overall"]["exit_code"])

    def test_shared_checkout_pattern_is_error(self):
        findings = []
        inventory.inspect_file_content(
            ".github/workflows/copilot-setup-steps.yml",
            "setup",
            "permissions: {}\njobs:\n  copilot-setup-steps:\n"
            "    steps:\n      - uses: actions/checkout@v4\n"
            "        with:\n          repository: frasermolyneux/.github-copilot\n",
            findings,
        )
        self.assertIn("legacy_shared_catalog", {item["code"] for item in findings})

    def test_mandatory_review_loop_is_error(self):
        findings = []
        inventory.inspect_file_content(
            "AGENTS.md",
            "agents_guidance",
            "You must run a review and repeat the review until there are no findings.",
            findings,
        )
        self.assertIn("mandatory_review_loop", {item["code"] for item in findings})

    def test_prohibitive_review_loop_documentation_is_suppressed(self):
        findings = []
        inventory.inspect_file_content(
            "AGENTS.md",
            "agents_guidance",
            "Do not run a mandatory review loop.",
            findings,
        )
        self.assertNotIn("mandatory_review_loop", {item["code"] for item in findings})

    def test_broad_apply_to_is_warning(self):
        findings = []
        inventory.inspect_instruction(
            ".github/instructions/all.instructions.md",
            "---\napplyTo: \"**/*\"\n---\nGuidance\n",
            findings,
        )
        self.assertIn("instruction_apply_to_broad", {item["code"] for item in findings})

    def test_manual_instruction_without_apply_to_is_compliant(self):
        findings = []
        inventory.inspect_instruction(
            ".github/instructions/manual.instructions.md",
            "---\nmanual: true\n---\nAttach manually.\n",
            findings,
        )
        self.assertEqual([], findings)

    def test_autonomous_agent_is_error(self):
        findings = []
        inventory.inspect_agent(
            ".github/agents/autonomous.agent.md",
            "---\nname: Autonomous\ntarget: github-copilot\n"
            "tools: [read, edit]\n---\nDelegate to a sub-agent and finish the change.\n",
            findings,
        )
        codes = {item["code"] for item in findings}
        self.assertIn("agent_model_invocable", codes)
        self.assertIn("agent_mutating_tool", codes)
        self.assertIn("agent_delegation", codes)

    def test_compliant_manual_only_custom_agent(self):
        findings = []
        inventory.inspect_agent(
            ".github/agents/manual.agent.md",
            "---\nname: Manual\ndisable-model-invocation: true\n"
            "user-invocable: true\ntarget: github-copilot\n"
            "tools: [read, search]\nmodel: inherit\n---\nInspect and report only.\n",
            findings,
        )
        self.assertEqual([], findings)

    def test_copilot_setup_v1_is_error(self):
        findings = []
        inventory.inspect_setup(
            ".github/workflows/copilot-setup-steps.yml",
            "permissions: {}\njobs:\n  copilot-setup-steps:\n"
            "    steps:\n      - uses: github/copilot-setup@v1\n",
            findings,
        )
        match = next(item for item in findings if item["code"] == "copilot_setup_v1")
        self.assertEqual("error", match["severity"])

    def test_runtime_only_v2_setup_is_compliant(self):
        findings = []
        inventory.inspect_setup(
            ".github/workflows/copilot-setup-steps.yml",
            "permissions: {}\njobs:\n  copilot-setup-steps:\n"
            "    steps:\n      - uses: actions/setup-python@v2\n"
            "        with:\n          python-version: '3.12'\n",
            findings,
        )
        self.assertEqual([], findings)

    def test_setup_build_or_test_is_warning(self):
        findings = []
        inventory.inspect_setup(
            ".github/workflows/copilot-setup-steps.yml",
            "permissions: {}\njobs:\n  copilot-setup-steps:\n"
            "    steps:\n      - run: dotnet test\n",
            findings,
        )
        match = next(
            item for item in findings if item["code"] == "setup_build_test_or_browser"
        )
        self.assertEqual("warning", match["severity"])

    def test_setup_terraform_plan_is_error(self):
        findings = []
        inventory.inspect_setup(
            ".github/workflows/copilot-setup-steps.yml",
            "permissions: {}\njobs:\n  copilot-setup-steps:\n"
            "    steps:\n      - run: terraform plan\n",
            findings,
        )
        match = next(
            item for item in findings if item["code"] == "setup_prohibited_operation"
        )
        self.assertEqual("error", match["severity"])

    def test_mcp_known_path_and_server_count(self):
        findings = []
        count = inventory.inspect_file_content(
            ".vscode/mcp.json",
            "mcp",
            '{"servers":{"github":{"type":"http"},"local":{"command":"tool"}}}',
            findings,
        )
        self.assertEqual(2, count)
        self.assertIn(
            "repository_mcp_configuration", {item["code"] for item in findings}
        )

    def test_cataloged_mcp_exception_is_info(self):
        findings = []
        count = inventory.inspect_mcp(
            ".vscode/mcp.json",
            '{"servers":{"approved":{"type":"http"}}}',
            findings,
            approved=True,
        )
        self.assertEqual(1, count)
        self.assertEqual("info", findings[0]["severity"])

    def test_terraform_lock_is_error(self):
        findings = []
        inventory.inspect_file_content(
            "nested/.terraform.lock.hcl", "terraform_lock", "provider x {}", findings
        )
        self.assertIn("terraform_lock_tracked", {item["code"] for item in findings})

    def test_correct_review_rule(self):
        findings = []
        errors = []
        client = inventory.GitHubClient(
            None,
            transport=inventory.FixtureTransport(
                {
                    f"/repos/{OWNER}/repo/rulesets?includes_parents=false&per_page=100&page=1": response(
                        [{"id": 1}]
                    ),
                    f"/repos/{OWNER}/repo/rulesets/1": response(
                        {"rules": [canonical_rule()]}
                    ),
                }
            ),
            retries=0,
        )
        result = inventory.inspect_rulesets(
            client, OWNER, "repo", "required", findings, errors
        )
        self.assertTrue(result["canonical"])
        self.assertEqual([], findings)
        self.assertEqual([], errors)

    def test_duplicate_review_rules_are_error(self):
        responses = repo_responses("repo")
        responses[f"/repos/{OWNER}/repo/rulesets/7"] = response(
            {"id": 7, "rules": [canonical_rule(), canonical_rule()]}
        )
        report, _ = run_records([catalog_record()], responses)
        self.assertIn(
            "copilot_rule_count",
            {item["code"] for item in report["repositories"][0]["findings"]},
        )

    def test_review_on_push_enabled_is_error(self):
        report, _ = run_records(
            [catalog_record()],
            repo_responses("repo", rule=canonical_rule(push=True)),
        )
        self.assertIn(
            "copilot_rule_options",
            {item["code"] for item in report["repositories"][0]["findings"]},
        )

    def test_draft_review_enabled_is_error(self):
        report, _ = run_records(
            [catalog_record()],
            repo_responses("repo", rule=canonical_rule(draft=True)),
        )
        self.assertIn(
            "copilot_rule_options",
            {item["code"] for item in report["repositories"][0]["findings"]},
        )

    def test_duplicate_catalog_names_are_inconsistent(self):
        records, findings, duplicates = inventory.load_catalog(
            Path("unused"),
            [catalog_record("Repo"), catalog_record("repo")],
        )
        self.assertEqual(["Repo", "repo"], duplicates)
        self.assertTrue(
            any(item["code"] == "catalog_duplicate_repository" for item in findings)
        )
        self.assertTrue(
            all(record.classification == "unknown/inconsistent" for record in records)
        )

    def test_repository_catalog_explicit_states_are_consistent(self):
        records, findings, duplicates = inventory.load_catalog(
            Path("terraform/workloads")
        )
        by_name = {record.name: record for record in records}
        self.assertEqual([], duplicates)
        self.assertEqual([], findings)
        self.assertEqual("excluded", by_name["41-bovet-street"].classification)
        self.assertEqual("excluded", by_name["CoD4x_Server"].classification)
        self.assertEqual("decommissioned", by_name["portal-bots"].classification)
        self.assertEqual("empty", by_name["status-pages"].classification)
        self.assertEqual("active", by_name[".github"].classification)
        self.assertEqual("exempt", by_name[".github"].review_governance)

    def test_review_flags_true_are_error(self):
        report, _ = run_records(
            [catalog_record()],
            repo_responses("repo", rule=canonical_rule(draft=True, push=True)),
        )
        codes = {item["code"] for item in report["repositories"][0]["findings"]}
        self.assertIn("copilot_rule_options", codes)

    def test_metadata_404_is_incomplete(self):
        report, _ = run_records(
            [catalog_record()],
            {f"/repos/{OWNER}/repo": response({"message": "missing"}, 404)},
        )
        self.assertEqual(
            "missing/inaccessible", report["repositories"][0]["classification"]
        )
        self.assertEqual(2, report["overall"]["exit_code"])

    def test_tree_409_is_explicit_inconsistent_empty(self):
        responses = {
            f"/repos/{OWNER}/repo": response(metadata()),
            f"/repos/{OWNER}/repo/git/trees/main?recursive=1": response({}, 409),
        }
        report, _ = run_records([catalog_record()], responses)
        repo = report["repositories"][0]
        self.assertEqual("unknown/inconsistent", repo["classification"])
        self.assertIn(
            "tree_conflict_unclassified_empty",
            {item["code"] for item in repo["findings"]},
        )
        self.assertEqual(1, report["overall"]["exit_code"])

    def test_forbidden_and_rate_limit_are_distinct(self):
        forbidden = inventory.GitHubClient(
            None,
            transport=inventory.FixtureTransport(
                {"/repos/example/repo": response({}, 403)}
            ),
            retries=0,
        )
        with self.assertRaises(inventory.ForbiddenFailure):
            forbidden.get_json("/repos/example/repo")
        limited = inventory.GitHubClient(
            None,
            transport=inventory.FixtureTransport(
                {
                    "/repos/example/repo": response(
                        {}, 403, {"X-RateLimit-Remaining": "0"}
                    )
                }
            ),
            retries=0,
        )
        with self.assertRaises(inventory.RateLimitFailure):
            limited.get_json("/repos/example/repo")

    def test_malformed_json_is_explicit(self):
        client = inventory.GitHubClient(
            None,
            transport=inventory.FixtureTransport(
                {"/repos/example/repo": response("not-json")}
            ),
            retries=0,
        )
        with self.assertRaises(inventory.MalformedFailure):
            client.get_json("/repos/example/repo")

    def test_one_repository_failure_does_not_stop_next_repository(self):
        responses = {
            f"/repos/{OWNER}/bad": response({}, 404),
            **repo_responses("good"),
        }
        report, transport = run_records(
            [catalog_record("bad"), catalog_record("good")], responses
        )
        self.assertTrue(report["incomplete"])
        good = next(repo for repo in report["repositories"] if repo["name"] == "good")
        self.assertIsNotNone(good["ruleset"])
        self.assertTrue(
            any(request.endswith("/good/rulesets/7") for request in transport.requests)
        )

    def test_report_redacts_tokens_and_signed_urls(self):
        text = inventory.redact(
            "Authorization: Bearer ghp_abcdefghijklmnopqrstuvwxyz "
            "https://example.test/x?sig=secret&token=other secrets.MY_TOKEN"
        )
        self.assertNotIn("abcdefghijklmnopqrstuvwxyz", text)
        self.assertNotIn("sig=secret", text)
        self.assertNotIn("token=other", text)
        self.assertNotIn("MY_TOKEN", text)

    def test_stable_schema_and_no_baseline(self):
        report, _ = run_records([catalog_record()], repo_responses("repo"))
        inventory.validate_report_schema(report)
        self.assertEqual(inventory.SCHEMA_VERSION, report["schema_version"])
        self.assertEqual("first_run", report["growth"]["status"])
        self.assertEqual(
            inventory.MANUAL_CONTROL_NOTE, report["manual_controls"][0]["note"]
        )

    def test_error_and_incomplete_exit_is_deterministic(self):
        self.assertEqual(
            ("errors_and_incomplete", 3),
            inventory.overall_result(True, True, True),
        )

    def test_growth_baseline_comparison(self):
        baseline_path = SCRATCH / "baseline.json"
        baseline_path.write_text(
            json.dumps(
                {
                    "schema_version": inventory.SCHEMA_VERSION,
                    "totals": {
                        "repositories": 0,
                        "active_config_bytes": 0,
                        "instruction_files": 0,
                        "agent_files": 0,
                        "prompt_files": 0,
                        "skill_directories": 0,
                        "mcp_servers": 0,
                    },
                }
            ),
            encoding="utf-8",
        )
        current = {
            "repositories": inventory.THRESHOLDS["max_repository_growth"] + 1,
            "active_config_bytes": 0,
            "instruction_files": 0,
            "agent_files": 0,
            "prompt_files": 0,
            "skill_directories": 0,
            "mcp_servers": 0,
        }
        growth, findings = inventory.compare_baseline(current, baseline_path)
        self.assertEqual("investigation_required", growth["status"])
        self.assertEqual([], findings)

    def test_get_only_headers_and_no_token_in_error(self):
        captured = {}

        def transport(method, url, headers, timeout):
            captured.update(
                {"method": method, "url": url, "headers": dict(headers), "timeout": timeout}
            )
            return inventory.HttpResponse(500, {}, b"{}")

        client = inventory.GitHubClient(
            "ghp_supersecretvalue", transport=transport, retries=0
        )
        with self.assertRaises(inventory.TransientFailure) as raised:
            client.get_json("/repos/example/repo")
        self.assertEqual("GET", captured["method"])
        self.assertEqual(
            "Bearer ghp_supersecretvalue", captured["headers"]["Authorization"]
        )
        self.assertEqual(inventory.USER_AGENT, captured["headers"]["User-Agent"])
        self.assertEqual(inventory.API_VERSION, captured["headers"]["X-GitHub-Api-Version"])
        self.assertNotIn("supersecretvalue", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
