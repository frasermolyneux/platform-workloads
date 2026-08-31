#!/usr/bin/env python3
"""Read-only Copilot estate inventory for cataloged GitHub repositories."""

from __future__ import annotations

import argparse
import base64
import dataclasses
import datetime as dt
import email.utils
import fnmatch
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path, PurePosixPath
from typing import Any, Callable, Iterable, Mapping


SCHEMA_VERSION = "1.0"
INVENTORY_VERSION = "COP-315/1"
MANUAL_CONTROL_NOTE = (
    "COP-313: manual control—not API verified. Code-review MCP access is "
    "externally confirmed disabled because no suitable documented estate read "
    "API is available."
)
DEFAULT_OWNER = "frasermolyneux"
DEFAULT_TIMEOUT_SECONDS = 20
DEFAULT_RETRIES = 2
API_VERSION = "2022-11-28"
USER_AGENT = "platform-workloads-copilot-estate-inventory/1.0"
REPORT_JSON = "copilot-estate-inventory.json"
REPORT_MARKDOWN = "copilot-estate-inventory.md"

CHECKS = {
    "A": "Core repository guidance files and size measurements",
    "B": "Scoped instructions, agents, prompts, skills, setup, and MCP inventory",
    "C": "Tracked Terraform dependency lock files",
    "D": "Legacy shared Copilot catalog and checkout patterns",
    "E": "Mandatory or repeated review-loop instructions",
    "F": "Instruction frontmatter and applyTo scope",
    "G": "Custom-agent invocation, tools, target, and delegation",
    "H": "Copilot setup workflow static safety",
    "I": "Known MCP configuration paths",
    "J": "Canonical Copilot code-review ruleset",
}

# Centralized audit thresholds. Baselines measure change; these cap unusual absolute
# size/counts and baseline deltas that merit investigation without failing the audit.
THRESHOLDS = {
    "max_relevant_file_bytes": 128 * 1024,
    "max_config_bytes_per_repository": 512 * 1024,
    "max_combined_core_bytes": 64 * 1024,
    "max_instruction_files_per_repository": 50,
    "max_agent_files_per_repository": 25,
    "max_prompt_files_per_repository": 50,
    "max_skill_files_per_repository": 25,
    "max_mcp_servers_per_repository": 20,
    "max_repository_growth": 5,
    "max_config_bytes_growth": 128 * 1024,
    "max_instruction_file_growth": 5,
    "max_agent_file_growth": 3,
    "max_prompt_file_growth": 5,
    "max_skill_file_growth": 3,
    "max_mcp_server_growth": 3,
    "core_file_growth_bytes": 1024,
    "core_file_growth_percent": 25,
    "automatic_instruction_growth_bytes": 2048,
    "automatic_instruction_growth_percent": 25,
}

KNOWN_MCP_PATHS = {
    ".mcp.json",
    ".vscode/mcp.json",
    ".github/mcp.json",
    ".github/copilot-mcp.json",
    ".copilot/mcp.json",
    ".copilot/mcp-config.json",
    "mcp.json",
}

TEXT_SUFFIXES = {
    ".md",
    ".markdown",
    ".json",
    ".yaml",
    ".yml",
    ".toml",
    ".txt",
}

SECRET_PATTERNS = [
    re.compile(r"(?i)\b(authorization|proxy-authorization)\s*:\s*\S+"),
    re.compile(r"(?i)\b(bearer|token)\s+[A-Za-z0-9._~+/=-]+"),
    re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"),
    re.compile(r"(?i)([?&](?:token|access_token|sig|signature|x-amz-signature)=)[^&#\s]+"),
    re.compile(r"(?i)(secrets\.[A-Za-z0-9_]+)"),
]

LEGACY_PATTERNS = [
    re.compile(r"(?i)\bcheckout-shared-copilot\b"),
    re.compile(
        r"(?i)\brepository\s*:\s*['\"]?frasermolyneux/(?:\.github-copilot|\.github)\b"
    ),
    re.compile(r"(?i)\bpath\s*:\s*['\"]?[^#\n]*(?:shared-copilot|\.github-copilot)\b"),
    re.compile(r"(?i)\b(?:checkout|clone|download)\b[^#\n]*(?:shared-copilot|\.github-copilot)\b"),
    re.compile(r"(?i)github\.com/frasermolyneux/(?:\.github-copilot|\.github)/(?:raw|blob)/"),
    re.compile(r"(?i)(?:^|[\s'\"=/\\])\.github-copilot(?:[/\\]|\b)"),
    re.compile(r"(?i)\b(?:must|required to)\b.{0,80}\bread\b.{0,80}\bshared catalog\b"),
    re.compile(r"(?i)\bMCP\b.{0,80}\b(?:and|plus)\b.{0,40}\b(?:file|instruction)\b"),
]

REVIEW_LOOP_PATTERNS = [
    re.compile(r"(?i)\breview\s+loop\b"),
    re.compile(r"(?i)\brepeat\b.{0,80}\breview\b.{0,80}\buntil\b"),
    re.compile(r"(?i)\buntil\b.{0,80}\b(?:no findings|approved|passes)\b"),
    re.compile(r"(?i)\b(?:must|required to|always)\b.{0,60}\b(?:request|run|perform)\b.{0,30}\breview\b"),
    re.compile(r"(?i)\b(?:high|medium)\b.{0,40}\bfinding\b.{0,60}\b(?:fix|remediat)\b"),
    re.compile(r"(?i)\breview attestation\b"),
    re.compile(r"(?i)\bworkflow[- ]fixer\b.{0,60}\b(?:review|code-review)\b"),
    re.compile(r"(?i)\b(?:must|required to)\b.{0,50}\b(?:create|open)\b.{0,20}\bpull request\b"),
]

PROHIBITIVE_PREFIXES = (
    "do not ",
    "don't ",
    "must not ",
    "never ",
    "avoid ",
    "not required",
    "is not required",
    "historically ",
    "previously ",
)

MUTATING_TOOL_PATTERN = re.compile(
    r"(?i)(?:^|[-_.:/])(?:write|edit|create|delete|remove|apply|push|commit|merge|"
    r"issue|pull-request|shell|bash|powershell|execute|run-command)(?:$|[-_.:/])"
)
DELEGATION_PATTERN = re.compile(
    r"(?i)\b(?:delegate\s+to|delegat(?:e|ion)|sub-?agent|runSubagent|spawn\s+an?\s+agent)\b"
)
SETUP_PROHIBITED_PATTERN = re.compile(
    r"(?i)\b(?:terraform\s+(?:plan|apply)|"
    r"(?:deploy|publish)(?:ment|ing)?\b|"
    r"docker\s+push\b|gh\s+release\b|az\s+(?:deployment|webapp|functionapp)\b)"
)
SETUP_ADVISORY_PATTERN = re.compile(
    r"(?i)\b(?:dotnet\s+(?:build|test|format|pack)|"
    r"npm\s+(?:test|pack|run\s+(?:build|format))|"
    r"pnpm\s+(?:test|build|format|pack)|yarn\s+(?:test|build|format|pack)|"
    r"pytest\b|python\s+-m\s+unittest\b|"
    r"(?:make|cargo|go)\s+(?:build|test)|"
    r"playwright\s+install\b|install.*(?:browser|chromium|firefox|webkit))"
)


def redact(value: Any) -> str:
    """Return a bounded string with credentials and signed query values removed."""
    text = str(value)
    for pattern in SECRET_PATTERNS:
        if pattern.pattern.startswith("(?i)([?&]"):
            text = pattern.sub(r"\1[REDACTED]", text)
        elif "secrets\\." in pattern.pattern:
            text = pattern.sub("[REDACTED_SECRET_REFERENCE]", text)
        else:
            text = pattern.sub("[REDACTED]", text)
    return text[:1000]


def utc_timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


@dataclasses.dataclass
class HttpResponse:
    status: int
    headers: Mapping[str, str]
    body: bytes


class InventoryFailure(Exception):
    kind = "error"

    def __init__(self, message: str, *, path: str = "", status: int | None = None):
        super().__init__(redact(message))
        self.path = path
        self.status = status


class NotFoundFailure(InventoryFailure):
    kind = "not_found"


class ForbiddenFailure(InventoryFailure):
    kind = "forbidden"


class RateLimitFailure(InventoryFailure):
    kind = "rate_limit"


class ConflictFailure(InventoryFailure):
    kind = "conflict"


class MalformedFailure(InventoryFailure):
    kind = "malformed"


class TransientFailure(InventoryFailure):
    kind = "transient"


Transport = Callable[[str, str, Mapping[str, str], int], HttpResponse]


class UrlLibTransport:
    def __call__(
        self, method: str, url: str, headers: Mapping[str, str], timeout: int
    ) -> HttpResponse:
        if method != "GET":
            raise ValueError("The inventory transport structurally permits GET only")
        request = urllib.request.Request(url, headers=dict(headers), method="GET")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return HttpResponse(
                    status=response.status,
                    headers=dict(response.headers.items()),
                    body=response.read(),
                )
        except urllib.error.HTTPError as exc:
            return HttpResponse(
                status=exc.code,
                headers=dict(exc.headers.items()) if exc.headers else {},
                body=exc.read(),
            )
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise TransientFailure(f"GitHub GET transport failed: {exc}") from exc


class FixtureTransport:
    """Offline transport backed by exact path-and-query response fixtures."""

    def __init__(self, responses: Mapping[str, Any]):
        self.responses = dict(responses)
        self.requests: list[str] = []

    def __call__(
        self, method: str, url: str, headers: Mapping[str, str], timeout: int
    ) -> HttpResponse:
        if method != "GET":
            raise AssertionError("Fixture transport received a non-GET request")
        parsed = urllib.parse.urlsplit(url)
        key = parsed.path.removeprefix("/").replace("repos/", "/repos/", 1)
        if not key.startswith("/"):
            key = "/" + key
        if parsed.query:
            key += "?" + parsed.query
        self.requests.append(key)
        fixture = self.responses.get(key)
        if fixture is None:
            return HttpResponse(404, {}, b'{"message":"fixture response not found"}')
        body = fixture.get("body", {})
        if isinstance(body, (dict, list)):
            body_bytes = json.dumps(body).encode("utf-8")
        else:
            body_bytes = str(body).encode("utf-8")
        return HttpResponse(
            int(fixture.get("status", 200)),
            {str(k): str(v) for k, v in fixture.get("headers", {}).items()},
            body_bytes,
        )


class GitHubClient:
    def __init__(
        self,
        token: str | None,
        *,
        transport: Transport | None = None,
        timeout: int = DEFAULT_TIMEOUT_SECONDS,
        retries: int = DEFAULT_RETRIES,
        base_url: str = "https://api.github.com",
    ):
        self.transport = transport or UrlLibTransport()
        self.timeout = timeout
        self.retries = retries
        self.base_url = base_url.rstrip("/")
        self.rate_limit: dict[str, Any] = {}
        self.headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": API_VERSION,
            "User-Agent": USER_AGENT,
        }
        if token:
            self.headers["Authorization"] = f"Bearer {token}"

    def _capture_rate_limit(self, headers: Mapping[str, str]) -> None:
        normalized = {key.lower(): value for key, value in headers.items()}
        for source, target in (
            ("x-ratelimit-limit", "limit"),
            ("x-ratelimit-remaining", "remaining"),
            ("x-ratelimit-used", "used"),
            ("x-ratelimit-resource", "resource"),
            ("x-ratelimit-reset", "reset_epoch"),
        ):
            if source in normalized:
                value: Any = normalized[source]
                if target != "resource":
                    try:
                        value = int(value)
                    except ValueError:
                        pass
                self.rate_limit[target] = value

    def _url(self, path: str, params: Mapping[str, Any] | None) -> str:
        if not path.startswith("/"):
            raise ValueError("GitHub API paths must start with '/'")
        url = self.base_url + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        return url

    def get_json(
        self, path: str, params: Mapping[str, Any] | None = None
    ) -> tuple[Any, Mapping[str, str]]:
        """Perform one GET-only JSON request with bounded transient retries."""
        url = self._url(path, params)
        attempt = 0
        while True:
            try:
                response = self.transport("GET", url, self.headers, self.timeout)
            except TransientFailure:
                if attempt >= self.retries:
                    raise
                time.sleep(min(2**attempt, 2))
                attempt += 1
                continue
            self._capture_rate_limit(response.headers)
            status = response.status
            remaining = str(
                next(
                    (
                        value
                        for key, value in response.headers.items()
                        if key.lower() == "x-ratelimit-remaining"
                    ),
                    "",
                )
            )
            if status == 404:
                raise NotFoundFailure(
                    f"GitHub GET returned 404 for {path}", path=path, status=status
                )
            if status == 409:
                raise ConflictFailure(
                    f"GitHub GET returned 409 for {path}", path=path, status=status
                )
            if status == 403 and remaining == "0":
                raise RateLimitFailure(
                    f"GitHub GET rate limit exhausted for {path}",
                    path=path,
                    status=status,
                )
            if status == 403:
                raise ForbiddenFailure(
                    f"GitHub GET was forbidden for {path}", path=path, status=status
                )
            if status == 429:
                failure = RateLimitFailure(
                    f"GitHub GET was rate limited for {path}",
                    path=path,
                    status=status,
                )
                if attempt >= self.retries:
                    raise failure
                self._sleep_for_retry(response.headers, attempt)
                attempt += 1
                continue
            if status in {408, 425} or 500 <= status <= 599:
                failure = TransientFailure(
                    f"GitHub GET returned transient status {status} for {path}",
                    path=path,
                    status=status,
                )
                if attempt >= self.retries:
                    raise failure
                self._sleep_for_retry(response.headers, attempt)
                attempt += 1
                continue
            if not 200 <= status <= 299:
                raise InventoryFailure(
                    f"GitHub GET returned status {status} for {path}",
                    path=path,
                    status=status,
                )
            try:
                return json.loads(response.body.decode("utf-8")), response.headers
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise MalformedFailure(
                    f"GitHub GET returned malformed JSON for {path}: {exc}",
                    path=path,
                    status=status,
                ) from exc

    @staticmethod
    def _sleep_for_retry(headers: Mapping[str, str], attempt: int) -> None:
        normalized = {key.lower(): value for key, value in headers.items()}
        retry_after = normalized.get("retry-after")
        delay = min(2**attempt, 2)
        if retry_after:
            try:
                delay = min(float(retry_after), 5)
            except ValueError:
                try:
                    parsed = email.utils.parsedate_to_datetime(retry_after)
                    delay = max(
                        0,
                        min(
                            (parsed - dt.datetime.now(parsed.tzinfo)).total_seconds(),
                            5,
                        ),
                    )
                except (TypeError, ValueError):
                    pass
        time.sleep(delay)

    def get_paginated(self, path: str, params: Mapping[str, Any] | None = None) -> list[Any]:
        query = dict(params or {})
        query.setdefault("per_page", 100)
        page = 1
        collected: list[Any] = []
        while True:
            query["page"] = page
            payload, _ = self.get_json(path, query)
            if not isinstance(payload, list):
                raise MalformedFailure(
                    f"Expected a JSON list from {path}", path=path
                )
            collected.extend(payload)
            if len(payload) < int(query["per_page"]):
                return collected
            page += 1
            if page > 100:
                raise MalformedFailure(f"Pagination exceeded 100 pages for {path}")


@dataclasses.dataclass
class CatalogRecord:
    name: str
    path: str
    github: dict[str, Any]
    classification: str
    inspection: str
    review_governance: str
    reason: str
    consistent: bool = True
    approved_mcp_paths: tuple[str, ...] = ()


def finding(
    check: str,
    severity: str,
    code: str,
    message: str,
    *,
    path: str | None = None,
    line: int | None = None,
    evidence: str | None = None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "check": check,
        "severity": severity,
        "code": code,
        "message": redact(message),
    }
    if path:
        result["path"] = path
    if line is not None:
        result["line"] = line
    if evidence:
        result["evidence"] = redact(evidence.strip())[:300]
    return result


def classify_catalog_entry(
    data: Mapping[str, Any], path: str
) -> tuple[CatalogRecord, list[dict[str, Any]]]:
    issues: list[dict[str, Any]] = []
    name = data.get("name")
    github = data.get("github")
    if not isinstance(name, str) or not name.strip() or not isinstance(github, dict):
        synthetic = name if isinstance(name, str) and name else PurePosixPath(path).stem
        record = CatalogRecord(
            synthetic,
            path,
            github if isinstance(github, dict) else {},
            "unknown/inconsistent",
            "none",
            "exempt",
            "Catalog record is missing a valid name or github object",
            False,
        )
        issues.append(
            finding(
                "B",
                "error",
                "catalog_invalid_record",
                "Catalog record must contain a non-empty name and github object",
                path=path,
            )
        )
        return record, issues

    policy = github.get("repository_policy", {})
    copilot_policy = policy.get("copilot_code_review", {}) if isinstance(policy, dict) else {}
    default_governance = (
        "required"
        if not isinstance(copilot_policy, dict)
        or copilot_policy.get("enabled", True) is not False
        else "exempt"
    )
    inventory = github.get("inventory")
    state = "active"
    inspection = "repository"
    governance = default_governance
    reason = ""
    approved_mcp_paths: tuple[str, ...] = ()
    consistent = True
    if inventory is not None:
        if not isinstance(inventory, dict):
            consistent = False
            issues.append(
                finding(
                    "B",
                    "error",
                    "catalog_inventory_invalid",
                    "github.inventory must be an object",
                    path=path,
                )
            )
        else:
            state = inventory.get("state", state)
            inspection = inventory.get("inspection", inspection)
            governance = inventory.get("review_governance", governance)
            reason = inventory.get("reason", "")
            approved = inventory.get("approved_mcp_paths", [])
            if isinstance(approved, list) and all(
                isinstance(item, str) and item.strip() for item in approved
            ):
                approved_mcp_paths = tuple(item.strip().lower() for item in approved)
            else:
                consistent = False
                issues.append(
                    finding(
                        "I",
                        "error",
                        "catalog_mcp_exception_invalid",
                        "github.inventory.approved_mcp_paths must be a list of non-empty paths",
                        path=path,
                    )
                )

    allowed_states = {"active", "empty", "excluded", "decommissioned"}
    allowed_inspection = {"repository", "metadata", "none"}
    allowed_governance = {"required", "exempt"}
    valid_combinations = {
        "active": {"repository"},
        "empty": {"metadata"},
        "excluded": {"none"},
        "decommissioned": {"none"},
    }
    if (
        state not in allowed_states
        or inspection not in allowed_inspection
        or governance not in allowed_governance
        or inspection not in valid_combinations.get(state, set())
        or (inventory is not None and not isinstance(reason, str))
        or (
            state in {"empty", "excluded", "decommissioned"}
            and not str(reason).strip()
        )
    ):
        consistent = False
        issues.append(
            finding(
                "B",
                "error",
                "catalog_inventory_inconsistent",
                "github.inventory contains an unsupported or inconsistent classification",
                path=path,
            )
        )
    if state in {"active", "empty"} and governance != default_governance:
        policy_enabled = (
            isinstance(copilot_policy, dict)
            and copilot_policy.get("enabled", True) is not False
        )
        if (governance == "exempt" and policy_enabled) or (
            governance == "required" and not policy_enabled
        ):
            consistent = False
            issues.append(
                finding(
                    "J",
                    "error",
                    "catalog_review_governance_inconsistent",
                    "Inventory review governance disagrees with repository_policy.copilot_code_review",
                    path=path,
                )
            )
    if github.get("visibility", "public") != "public" and state != "excluded":
        consistent = False
        issues.append(
            finding(
                "B",
                "error",
                "catalog_nonpublic_target",
                "Inspected catalog repositories must be public; private repositories must be excluded",
                path=path,
            )
        )
    classification = state if consistent else "unknown/inconsistent"
    return (
        CatalogRecord(
            name=name,
            path=path,
            github=dict(github),
            classification=classification,
            inspection=inspection if consistent else "none",
            review_governance=governance,
            reason=str(reason),
            consistent=consistent,
            approved_mcp_paths=approved_mcp_paths,
        ),
        issues,
    )


def load_catalog(
    root: Path, fixture_records: Iterable[Mapping[str, Any]] | None = None
) -> tuple[list[CatalogRecord], list[dict[str, Any]], list[str]]:
    records: list[CatalogRecord] = []
    issues: list[dict[str, Any]] = []
    if fixture_records is None:
        paths = sorted(
            path
            for path in root.rglob("*.json")
            if "examples" not in {part.lower() for part in path.relative_to(root).parts}
        )
        sources: list[tuple[str, Mapping[str, Any]]] = []
        for path in paths:
            relative = path.relative_to(root).as_posix()
            try:
                payload = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
                issues.append(
                    finding(
                        "B",
                        "error",
                        "catalog_malformed_json",
                        f"Catalog JSON could not be loaded: {exc}",
                        path=relative,
                    )
                )
                continue
            if not isinstance(payload, dict):
                issues.append(
                    finding(
                        "B",
                        "error",
                        "catalog_invalid_record",
                        "Catalog JSON root must be an object",
                        path=relative,
                    )
                )
                continue
            sources.append((relative, payload))
    else:
        sources = [
            (str(item.get("_path", f"fixture/{index}.json")), item)
            for index, item in enumerate(fixture_records)
        ]

    for path, payload in sources:
        record, record_issues = classify_catalog_entry(payload, path)
        records.append(record)
        issues.extend(record_issues)

    names: dict[str, list[CatalogRecord]] = {}
    for record in records:
        names.setdefault(record.name.casefold(), []).append(record)
    duplicates = sorted(
        record.name
        for duplicate_records in names.values()
        if len(duplicate_records) > 1
        for record in duplicate_records
    )
    for duplicate_records in names.values():
        if len(duplicate_records) <= 1:
            continue
        paths = ", ".join(record.path for record in duplicate_records)
        issues.append(
            finding(
                "B",
                "error",
                "catalog_duplicate_repository",
                f"Catalog repository name is duplicated: {paths}",
                path=duplicate_records[0].path,
            )
        )
        for record in duplicate_records:
            record.classification = "unknown/inconsistent"
            record.inspection = "none"
            record.consistent = False
    return records, issues, duplicates


def parse_scalar(value: str) -> Any:
    value = value.strip()
    if not value:
        return ""
    if value.lower() in {"true", "false"}:
        return value.lower() == "true"
    if value.lower() in {"null", "~"}:
        return None
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [parse_scalar(part) for part in inner.split(",")]
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    return value


def parse_frontmatter(text: str) -> tuple[dict[str, Any], str, str | None]:
    """Parse the simple flat YAML frontmatter used by Copilot configuration."""
    normalized = text.lstrip("\ufeff")
    lines = normalized.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, normalized, None
    end = next((index for index in range(1, len(lines)) if lines[index].strip() == "---"), None)
    if end is None:
        return {}, normalized, "Frontmatter opening delimiter has no closing delimiter"
    data: dict[str, Any] = {}
    active_list: str | None = None
    for raw in lines[1:end]:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("-") and active_list:
            data.setdefault(active_list, []).append(parse_scalar(stripped[1:].strip()))
            continue
        match = re.match(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$", stripped)
        if not match:
            return {}, "\n".join(lines[end + 1 :]), f"Unsupported frontmatter line: {stripped}"
        key, value = match.groups()
        parsed = parse_scalar(value)
        if value == "":
            parsed = []
            active_list = key
        else:
            active_list = None
        data[key] = parsed
    return data, "\n".join(lines[end + 1 :]), None


def path_kind(path: str) -> str | None:
    lowered = path.lower()
    name = PurePosixPath(lowered).name
    if lowered == "agents.md":
        return "agents_guidance"
    if lowered == ".github/copilot-instructions.md":
        return "copilot_instructions"
    if lowered.startswith(".github/instructions/") and lowered.endswith(".instructions.md"):
        return "instruction"
    if lowered.startswith(".github/agents/") and lowered.endswith(".agent.md"):
        return "agent"
    if lowered.startswith(".github/prompts/") and lowered.endswith(".prompt.md"):
        return "prompt"
    if (
        lowered.startswith(".github/skills/")
        and PurePosixPath(lowered).name == "skill.md"
    ):
        return "skill"
    if lowered in {
        ".github/workflows/copilot-setup-steps.yml",
        ".github/workflows/copilot-setup-steps.yaml",
    }:
        return "setup"
    if lowered.startswith(".github/workflows/") and lowered.endswith((".yml", ".yaml")):
        return "workflow"
    if lowered in KNOWN_MCP_PATHS:
        return "mcp"
    if name == ".terraform.lock.hcl":
        return "terraform_lock"
    return None


def relevant_text_path(path: str) -> bool:
    kind = path_kind(path)
    if kind:
        return True
    lowered = path.lower()
    suffix = PurePosixPath(lowered).suffix
    return (
        suffix in TEXT_SUFFIXES
        and not lowered.startswith(("docs/", ".git/", "vendor/", "node_modules/"))
        and (
            lowered.startswith(".github/")
            or lowered == "agents.md"
        )
    )


def decode_blob(payload: Any, path: str) -> str:
    if not isinstance(payload, dict):
        raise MalformedFailure(f"Blob response for {path} is not an object")
    content = payload.get("content")
    encoding = payload.get("encoding")
    if not isinstance(content, str) or encoding != "base64":
        raise MalformedFailure(f"Blob response for {path} is not base64 content")
    try:
        raw = base64.b64decode(content, validate=False)
        return raw.decode("utf-8")
    except (ValueError, UnicodeDecodeError) as exc:
        raise MalformedFailure(f"Blob response for {path} is not UTF-8 text") from exc


def evidence_matches(
    text: str, patterns: Iterable[re.Pattern[str]], *, suppress_prohibitive: bool
) -> Iterable[tuple[int, str]]:
    for line_number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        lowered = stripped.casefold()
        if suppress_prohibitive and any(prefix in lowered for prefix in PROHIBITIVE_PREFIXES):
            continue
        if any(pattern.search(line) for pattern in patterns):
            yield line_number, stripped


def instruction_summary(text: str) -> dict[str, Any]:
    frontmatter, _, error = parse_frontmatter(text)
    apply_to = frontmatter.get("applyTo")
    scopes = (
        apply_to
        if isinstance(apply_to, list)
        else ([apply_to] if apply_to is not None else [])
    )
    return {
        "description": frontmatter.get("description"),
        "apply_to": [str(scope).strip() for scope in scopes],
        "manual": frontmatter.get("manual") is True,
        "frontmatter_error": error,
    }


def inspect_instruction(
    path: str,
    text: str,
    findings: list[dict[str, Any]],
    repository_paths: Iterable[str] = (),
) -> None:
    if not text.lstrip("\ufeff").startswith("---"):
        findings.append(
            finding(
                "F",
                "warning",
                "instruction_frontmatter_missing",
                "Scoped instruction has no YAML-style frontmatter",
                path=path,
            )
        )
    frontmatter, _, error = parse_frontmatter(text)
    if error:
        findings.append(
            finding("F", "error", "instruction_frontmatter_malformed", error, path=path)
        )
        return
    apply_to = frontmatter.get("applyTo")
    manual = frontmatter.get("manual") is True
    if apply_to is None:
        if not manual:
            findings.append(
                finding(
                    "F",
                    "warning",
                    "instruction_apply_to_missing",
                    "Scoped instruction has no applyTo; add manual: true when omission is intentional",
                    path=path,
                )
            )
        return
    scopes = apply_to if isinstance(apply_to, list) else [apply_to]
    normalized = [str(value).strip() for value in scopes]
    if not normalized or any(value in {"", "*", "**", "**/*", "/**"} for value in normalized):
        findings.append(
            finding(
                "F",
                "warning",
                "instruction_apply_to_broad",
                "Instruction applyTo is empty or repository-wide",
                path=path,
                evidence=str(apply_to),
            )
        )
        return
    patterns = [
        pattern
        for scope in normalized
        for pattern in (part.strip() for part in scope.split(","))
        if pattern
    ]
    matched = any(
        fnmatch.fnmatchcase(candidate, pattern)
        or PurePosixPath(candidate).match(pattern)
        for candidate in repository_paths
        for pattern in patterns
    )
    if repository_paths and not matched:
        findings.append(
            finding(
                "F",
                "warning",
                "instruction_apply_to_no_match",
                "Instruction applyTo does not match the current repository tree",
                path=path,
                evidence=str(apply_to),
            )
        )


def normalized_tools(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value]
    if isinstance(value, str):
        return [item.strip() for item in value.split(",") if item.strip()]
    return [str(value)]


def inspect_agent(path: str, text: str, findings: list[dict[str, Any]]) -> None:
    if not text.lstrip("\ufeff").startswith("---"):
        findings.append(
            finding(
                "G",
                "error",
                "agent_frontmatter_missing",
                "Custom agent has no YAML-style frontmatter",
                path=path,
            )
        )
    frontmatter, body, error = parse_frontmatter(text)
    if error:
        findings.append(
            finding("G", "error", "agent_frontmatter_malformed", error, path=path)
        )
        return
    if frontmatter.get("disable-model-invocation") is not True:
        findings.append(
            finding(
                "G",
                "error",
                "agent_model_invocable",
                "Custom agent permits model invocation; manual-only agents must set disable-model-invocation: true",
                path=path,
            )
        )
    if frontmatter.get("user-invocable") is not True:
        findings.append(
            finding(
                "G",
                "warning",
                "agent_not_user_invocable",
                "Manual-only custom agent is not user invocable",
                path=path,
            )
        )
    target = frontmatter.get("target")
    if target not in {"github-copilot", "vscode"}:
        findings.append(
            finding(
                "G",
                "warning",
                "agent_target_missing_or_unknown",
                "Custom agent target should be github-copilot or vscode",
                path=path,
                evidence=str(target),
            )
        )
    tools = normalized_tools(frontmatter.get("tools"))
    if len(tools) > 10 or any(tool.strip().lower() in {"*", "all", "all-tools"} for tool in tools):
        findings.append(
            finding(
                "G",
                "warning",
                "agent_tools_broad",
                "Custom agent declares unrestricted or unexpectedly broad tools",
                path=path,
                evidence=", ".join(tools),
            )
        )
    for tool in tools:
        if MUTATING_TOOL_PATTERN.search(tool):
            findings.append(
                finding(
                    "G",
                    "error",
                    "agent_mutating_tool",
                    "Custom agent declares a potentially mutating or command-execution tool",
                    path=path,
                    evidence=tool,
                )
            )
    for line_number, line in evidence_matches(
        body, [DELEGATION_PATTERN], suppress_prohibitive=True
    ):
        findings.append(
            finding(
                "G",
                "error",
                "agent_delegation",
                "Custom agent directs delegation or sub-agent execution",
                path=path,
                line=line_number,
                evidence=line,
            )
        )


def setup_summary(text: str) -> dict[str, Any]:
    actions: list[str] = []
    commands: list[str] = []
    runtimes: list[dict[str, Any]] = []
    checkout_repositories: list[str] = []
    runner = None
    permissions: list[str] = []
    lines = text.splitlines()
    for index, line in enumerate(lines):
        action_match = re.search(r"\buses\s*:\s*([^\s#]+)", line)
        if action_match:
            action = action_match.group(1)
            actions.append(action)
            runtime_match = re.search(r"actions/setup-([a-z0-9_-]+)", action, re.I)
            if runtime_match:
                version = None
                for following in lines[index + 1 : index + 8]:
                    version_match = re.search(
                        r"^\s*(?:[a-z0-9_-]+-version|version)\s*:\s*['\"]?([^'\"#\s]+)",
                        following,
                        re.I,
                    )
                    if version_match:
                        version = version_match.group(1)
                        break
                    if re.search(r"^\s*-\s+(?:name|uses|run)\s*:", following):
                        break
                runtimes.append({"runtime": runtime_match.group(1), "version": version})
        run_match = re.search(r"\brun\s*:\s*(.*)$", line)
        if run_match:
            commands.append(run_match.group(1).strip())
        repository_match = re.search(
            r"^\s*(?:repository|checkout-repo)\s*:\s*['\"]?([^'\"#\s]+)",
            line,
        )
        if repository_match:
            checkout_repositories.append(repository_match.group(1))
        runner_match = re.search(r"^\s*runs-on\s*:\s*(.+?)\s*$", line)
        if runner_match:
            runner = runner_match.group(1).strip("'\"")
        permission_match = re.search(
            r"^\s{2,}(actions|checks|contents|deployments|id-token|issues|packages|"
            r"pages|pull-requests|security-events|statuses)\s*:\s*(read|write)\s*$",
            line,
        )
        if permission_match:
            permissions.append(
                f"{permission_match.group(1)}:{permission_match.group(2)}"
            )
    return {
        "actions": actions,
        "commands": commands,
        "checkout_repositories": checkout_repositories,
        "runtimes": runtimes,
        "runner": runner,
        "permissions": permissions,
    }


def inspect_setup(path: str, text: str, findings: list[dict[str, Any]]) -> None:
    if not re.search(r"(?m)^\s*copilot-setup-steps\s*:", text):
        findings.append(
            finding(
                "H",
                "error",
                "setup_job_missing",
                "Copilot setup workflow must define the copilot-setup-steps job",
                path=path,
            )
        )
    if not re.search(r"(?m)^\s*permissions\s*:\s*\{\s*\}\s*$", text):
        findings.append(
            finding(
                "H",
                "warning",
                "setup_permissions_not_empty",
                "Copilot setup workflow should declare permissions: {}",
                path=path,
            )
        )
    for line_number, line in enumerate(text.splitlines(), 1):
        action_match = re.search(r"\buses\s*:\s*([^\s#]+)", line)
        if action_match:
            action = action_match.group(1)
            if re.search(r"(?i)copilot-setup[^@\s]*@v1(?:\D|$)", action):
                findings.append(
                    finding(
                        "H",
                        "error",
                        "copilot_setup_v1",
                        "Copilot setup workflow uses prohibited copilot-setup/v1",
                        path=path,
                        line=line_number,
                        evidence=action,
                    )
                )
            if "@" not in action:
                findings.append(
                    finding(
                        "H",
                        "warning",
                        "setup_action_unpinned",
                        "Copilot setup workflow action is unpinned",
                        path=path,
                        line=line_number,
                        evidence=action,
                    )
                )
        run_match = re.search(r"\brun\s*:\s*(.*)$", line)
        if run_match and SETUP_PROHIBITED_PATTERN.search(run_match.group(1)):
            findings.append(
                finding(
                    "H",
                    "error",
                    "setup_prohibited_operation",
                    "Copilot setup workflow performs plan, apply, deployment, or publication work",
                    path=path,
                    line=line_number,
                    evidence=run_match.group(1),
                )
            )
        elif run_match and SETUP_ADVISORY_PATTERN.search(run_match.group(1)):
            findings.append(
                finding(
                    "H",
                    "warning",
                    "setup_build_test_or_browser",
                    "Copilot setup workflow performs build, test, format, pack, or browser installation work",
                    path=path,
                    line=line_number,
                    evidence=run_match.group(1),
                )
            )
    summary = setup_summary(text)
    for runtime in summary["runtimes"]:
        if not runtime["version"]:
            findings.append(
                finding(
                    "H",
                    "warning",
                    "setup_runtime_version_missing",
                    f"Runtime setup does not declare an explicit version: {runtime['runtime']}",
                    path=path,
                )
            )
    if len(summary["runtimes"]) > 2:
        findings.append(
            finding(
                "H",
                "warning",
                "setup_multiple_runtimes",
                "Copilot setup configures more than two runtimes; confirm each is a prerequisite",
                path=path,
            )
        )
    if any(permission.endswith(":write") for permission in summary["permissions"]):
        findings.append(
            finding(
                "H",
                "warning",
                "setup_excessive_permissions",
                "Copilot setup workflow declares write permissions",
                path=path,
                evidence=", ".join(summary["permissions"]),
            )
        )
    checkout_actions = [
        action
        for action in summary["actions"]
        if action.lower().startswith("actions/checkout@")
    ]
    if checkout_actions and not re.search(
        r"(?i)\b(?:restore|private dependenc|git lfs|lfs:|submodules:)\b", text
    ):
        findings.append(
            finding(
                "H",
                "warning",
                "setup_checkout_reason_unclear",
                "Repository checkout has no demonstrated restore, private dependency, LFS, or submodule prerequisite",
                path=path,
            )
        )
    if len(checkout_actions) > 1 or summary["checkout_repositories"]:
        findings.append(
            finding(
                "H",
                "warning",
                "setup_additional_checkout",
                "Copilot setup performs an additional or cross-repository checkout",
                path=path,
                evidence=", ".join(summary["checkout_repositories"]),
            )
        )
    if not summary["runtimes"] and not summary["commands"] and not summary[
        "checkout_repositories"
    ]:
        findings.append(
            finding(
                "H",
                "warning",
                "setup_no_prerequisite",
                "Copilot setup workflow appears to provide no pre-agent prerequisite",
                path=path,
            )
        )


def inspect_mcp(
    path: str, text: str, findings: list[dict[str, Any]], *, approved: bool = False
) -> int:
    findings.append(
        finding(
            "I",
            "info" if approved else "error",
            "repository_mcp_exception" if approved else "repository_mcp_configuration",
            (
                "Tracked repository MCP configuration is covered by a canonical catalog exception"
                if approved
                else "Tracked repository MCP configuration is prohibited without a cataloged exception"
            ),
            path=path,
        )
    )
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        findings.append(
            finding(
                "I",
                "error",
                "mcp_malformed_json",
                f"MCP configuration is malformed JSON: {exc}",
                path=path,
            )
        )
        return 0
    if not isinstance(payload, dict):
        findings.append(
            finding(
                "I",
                "error",
                "mcp_invalid_root",
                "MCP configuration root must be an object",
                path=path,
            )
        )
        return 0
    servers = payload.get("servers", payload.get("mcpServers", {}))
    if not isinstance(servers, dict):
        findings.append(
            finding(
                "I",
                "error",
                "mcp_servers_invalid",
                "MCP servers must be represented by an object",
                path=path,
            )
        )
        return 0
    return len(servers)


def inspect_file_content(
    path: str,
    kind: str | None,
    text: str,
    findings: list[dict[str, Any]],
    repository_paths: Iterable[str] = (),
    approved_mcp: bool = False,
) -> int:
    if kind == "terraform_lock":
        findings.append(
            finding(
                "C",
                "error",
                "terraform_lock_tracked",
                "Tracked .terraform.lock.hcl files are prohibited by repository policy",
                path=path,
            )
        )
    if kind == "instruction":
        inspect_instruction(path, text, findings, repository_paths)
    if kind == "agent":
        inspect_agent(path, text, findings)
    if kind == "setup":
        inspect_setup(path, text, findings)

    pattern_source = kind in {
        "agents_guidance",
        "copilot_instructions",
        "instruction",
        "agent",
        "prompt",
        "setup",
        "workflow",
    }
    if pattern_source:
        for line_number, line in evidence_matches(
            text, LEGACY_PATTERNS, suppress_prohibitive=True
        ):
            findings.append(
                finding(
                    "D",
                    "error",
                    "legacy_shared_catalog",
                    "Repository-native configuration references a legacy shared Copilot catalog",
                    path=path,
                    line=line_number,
                    evidence=line,
                )
            )
    if kind in {"agents_guidance", "copilot_instructions", "instruction", "agent", "prompt"}:
        for line_number, line in evidence_matches(
            text, REVIEW_LOOP_PATTERNS, suppress_prohibitive=True
        ):
            findings.append(
                finding(
                    "E",
                    "error",
                    "mandatory_review_loop",
                    "Repository guidance mandates or repeats a review loop",
                    path=path,
                    line=line_number,
                    evidence=line,
                )
            )
    return (
        inspect_mcp(path, text, findings, approved=approved_mcp)
        if kind == "mcp"
        else 0
    )


def empty_measurements() -> dict[str, Any]:
    return {
        "tree_files": 0,
        "tree_bytes": 0,
        "relevant_files": 0,
        "config_bytes": 0,
        "config_lines": 0,
        "active_config_bytes": 0,
        "active_config_lines": 0,
        "automatic_instruction_bytes": 0,
        "automatic_instruction_lines": 0,
        "files": [],
        "core": {
            "agents": {"exists": False, "bytes": 0, "lines": 0},
            "copilot_instructions": {"exists": False, "bytes": 0, "lines": 0},
            "combined_bytes": 0,
            "combined_lines": 0,
        },
        "scoped": {
            "instruction_files": 0,
            "agent_files": 0,
            "prompt_files": 0,
            "skill_directories": 0,
            "setup_workflows": 0,
            "mcp_files": 0,
            "mcp_servers": 0,
        },
        "terraform_lock_files": 0,
        "fetched_files": 0,
        "skipped_large_files": 0,
    }


def apply_absolute_thresholds(
    measurements: Mapping[str, Any], findings: list[dict[str, Any]]
) -> None:
    scoped = measurements["scoped"]
    checks = [
        (
            measurements["active_config_bytes"],
            THRESHOLDS["max_config_bytes_per_repository"],
            "config_bytes_threshold",
            "Repository Copilot configuration bytes exceed the investigation threshold",
        ),
        (
            measurements["core"]["combined_bytes"],
            THRESHOLDS["max_combined_core_bytes"],
            "combined_core_bytes_threshold",
            "Combined core Copilot configuration exceeds the advisory threshold",
        ),
        (
            scoped["instruction_files"],
            THRESHOLDS["max_instruction_files_per_repository"],
            "instruction_count_threshold",
            "Instruction file count exceeds the investigation threshold",
        ),
        (
            scoped["agent_files"],
            THRESHOLDS["max_agent_files_per_repository"],
            "agent_count_threshold",
            "Custom-agent file count exceeds the investigation threshold",
        ),
        (
            scoped["prompt_files"],
            THRESHOLDS["max_prompt_files_per_repository"],
            "prompt_count_threshold",
            "Prompt file count exceeds the investigation threshold",
        ),
        (
            scoped["skill_directories"],
            THRESHOLDS["max_skill_files_per_repository"],
            "skill_count_threshold",
            "Skill file count exceeds the investigation threshold",
        ),
        (
            scoped["mcp_servers"],
            THRESHOLDS["max_mcp_servers_per_repository"],
            "mcp_count_threshold",
            "MCP server count exceeds the investigation threshold",
        ),
    ]
    for actual, maximum, code, message in checks:
        if actual > maximum:
            findings.append(
                finding(
                    "B",
                    "warning",
                    code,
                    f"{message}: {actual} > {maximum}",
                )
            )


def inspect_rulesets(
    client: GitHubClient,
    owner: str,
    name: str,
    governance: str,
    findings: list[dict[str, Any]],
    incomplete_errors: list[dict[str, Any]],
) -> dict[str, Any]:
    path = f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(name)}/rulesets"
    details: list[Any] = []
    try:
        rulesets = client.get_paginated(path, {"includes_parents": "false"})
    except InventoryFailure as exc:
        incomplete_errors.append(failure_record(name, "ruleset_list", exc))
        return {"rulesets": 0, "copilot_rules": 0, "details_complete": False}
    for ruleset in rulesets:
        ruleset_id = ruleset.get("id") if isinstance(ruleset, dict) else None
        if ruleset_id is None:
            incomplete_errors.append(
                {
                    "repository": name,
                    "operation": "ruleset_detail",
                    "kind": "malformed",
                    "message": "Ruleset list item did not contain an id",
                }
            )
            continue
        try:
            detail, _ = client.get_json(f"{path}/{ruleset_id}")
            details.append(detail)
        except InventoryFailure as exc:
            incomplete_errors.append(failure_record(name, "ruleset_detail", exc))

    copilot_rules: list[dict[str, Any]] = []
    ruleset_summaries: list[dict[str, Any]] = []
    for detail in details:
        if not isinstance(detail, dict) or not isinstance(detail.get("rules", []), list):
            incomplete_errors.append(
                {
                    "repository": name,
                    "operation": "ruleset_detail",
                    "kind": "malformed",
                    "message": "Ruleset detail did not contain a rules list",
                }
            )
            continue
        enforcement = detail.get("enforcement", "active")
        ruleset_summaries.append(
            {
                "id": detail.get("id"),
                "name": detail.get("name"),
                "target": detail.get("target"),
                "enforcement": enforcement,
                "rule_types": [
                    rule.get("type")
                    for rule in detail["rules"]
                    if isinstance(rule, dict)
                ],
            }
        )
        if enforcement != "active":
            continue
        for rule in detail["rules"]:
            if isinstance(rule, dict) and rule.get("type") == "copilot_code_review":
                copilot_rules.append(rule)

    if governance == "required":
        if len(copilot_rules) != 1:
            findings.append(
                finding(
                    "J",
                    "error",
                    "copilot_rule_count",
                    f"Governed repository must have exactly one copilot_code_review rule; found {len(copilot_rules)}",
                )
            )
        elif not canonical_copilot_rule(copilot_rules[0]):
            findings.append(
                finding(
                    "J",
                    "error",
                    "copilot_rule_options",
                    "copilot_code_review must set review_draft_pull_requests=false and review_on_push=false",
                )
            )
    elif copilot_rules:
        findings.append(
            finding(
                "J",
                "error",
                "copilot_rule_on_exempt_repository",
                f"Review-exempt repository has {len(copilot_rules)} copilot_code_review rule(s)",
            )
        )
    return {
        "rulesets": len(rulesets),
        "items": ruleset_summaries,
        "details_fetched": len(details),
        "copilot_rules": len(copilot_rules),
        "canonical": len(copilot_rules) == 1 and canonical_copilot_rule(copilot_rules[0]),
        "details_complete": len(details) == len(rulesets),
    }


def canonical_copilot_rule(rule: Mapping[str, Any]) -> bool:
    parameters = rule.get("parameters", rule)
    return (
        isinstance(parameters, dict)
        and parameters.get("review_draft_pull_requests") is False
        and parameters.get("review_on_push") is False
    )


def failure_record(repository: str, operation: str, exc: InventoryFailure) -> dict[str, Any]:
    result = {
        "repository": repository,
        "operation": operation,
        "kind": exc.kind,
        "message": redact(exc),
    }
    if exc.status is not None:
        result["status"] = exc.status
    return result


def inspect_repository(
    record: CatalogRecord, owner: str, client: GitHubClient
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "name": record.name,
        "catalog_path": record.path,
        "classification": record.classification,
        "inspection": record.inspection,
        "review_governance": record.review_governance,
        "reason": record.reason or None,
        "metadata": None,
        "measurements": empty_measurements(),
        "ruleset": None,
        "findings": [],
        "errors": [],
        "incomplete": False,
    }
    findings = result["findings"]
    incomplete_errors = result["errors"]
    if record.classification in {"excluded", "decommissioned", "unknown/inconsistent"}:
        return result

    repo_path = f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(record.name)}"
    try:
        metadata, _ = client.get_json(repo_path)
    except InventoryFailure as exc:
        result["classification"] = "missing/inaccessible"
        incomplete_errors.append(failure_record(record.name, "metadata", exc))
        result["incomplete"] = True
        return result
    if not isinstance(metadata, dict):
        exc = MalformedFailure("Repository metadata response was not an object")
        result["classification"] = "missing/inaccessible"
        incomplete_errors.append(failure_record(record.name, "metadata", exc))
        result["incomplete"] = True
        return result

    result["metadata"] = {
        "archived": bool(metadata.get("archived")),
        "disabled": bool(metadata.get("disabled")),
        "default_branch": metadata.get("default_branch"),
        "size_kib": metadata.get("size"),
        "visibility": metadata.get("visibility"),
        "private": metadata.get("private"),
    }
    if metadata.get("visibility") == "private" or metadata.get("private") is True:
        result["classification"] = "unknown/inconsistent"
        findings.append(
            finding(
                "B",
                "error",
                "metadata_private_target",
                "Inspected repository is private but catalog policy requires private repositories to be excluded",
            )
        )
        return result
    if metadata.get("archived") or metadata.get("disabled"):
        result["classification"] = "archived/disabled"
        result["inspection"] = "metadata"
        return result

    default_branch = metadata.get("default_branch")
    if record.classification == "empty":
        if default_branch is not None or int(metadata.get("size") or 0) > 0:
            result["classification"] = "unknown/inconsistent"
            findings.append(
                finding(
                    "B",
                    "error",
                    "empty_classification_inconsistent",
                    "Catalog marks repository empty but GitHub metadata reports content or a default branch",
                )
            )
        return result
    if default_branch is None:
        result["classification"] = "unknown/inconsistent"
        result["inspection"] = "metadata"
        findings.append(
            finding(
                "B",
                "error",
                "unclassified_empty_repository",
                "Repository has no default branch; add an explicit empty inventory classification",
            )
        )
        return result

    tree_path = (
        f"{repo_path}/git/trees/"
        f"{urllib.parse.quote(str(default_branch), safe='')}?recursive=1"
    )
    try:
        tree, _ = client.get_json(tree_path)
        if not isinstance(tree, dict) or not isinstance(tree.get("tree"), list):
            raise MalformedFailure("Recursive tree response did not contain a tree list")
        if tree.get("truncated") is True:
            incomplete_errors.append(
                {
                    "repository": record.name,
                    "operation": "recursive_tree",
                    "kind": "truncated",
                    "message": "GitHub recursive tree response was truncated",
                }
            )
        inspect_tree(record, repo_path, tree["tree"], client, result)
    except ConflictFailure:
        result["classification"] = "unknown/inconsistent"
        result["inspection"] = "metadata"
        findings.append(
            finding(
                "B",
                "error",
                "tree_conflict_unclassified_empty",
                "GitHub returned 409 for the default-branch tree; classify an empty repository explicitly",
            )
        )
        return result
    except InventoryFailure as exc:
        incomplete_errors.append(failure_record(record.name, "recursive_tree", exc))

    result["ruleset"] = inspect_rulesets(
        client,
        owner,
        record.name,
        record.review_governance,
        findings,
        incomplete_errors,
    )
    result["incomplete"] = bool(incomplete_errors)
    apply_absolute_thresholds(result["measurements"], findings)
    return result


def inspect_tree(
    record: CatalogRecord,
    repo_path: str,
    entries: list[Any],
    client: GitHubClient,
    result: dict[str, Any],
) -> None:
    measurements = result["measurements"]
    findings = result["findings"]
    files = [
        entry
        for entry in entries
        if isinstance(entry, dict)
        and entry.get("type") == "blob"
        and isinstance(entry.get("path"), str)
    ]
    measurements["tree_files"] = len(files)
    measurements["tree_bytes"] = sum(
        int(entry.get("size") or 0) for entry in files if isinstance(entry.get("size"), int)
    )
    relevant = [entry for entry in files if relevant_text_path(entry["path"])]
    measurements["relevant_files"] = len(relevant)
    kinds = Counter(path_kind(entry["path"]) for entry in relevant)
    measurements["scoped"]["instruction_files"] = kinds["instruction"]
    measurements["scoped"]["agent_files"] = kinds["agent"]
    measurements["scoped"]["prompt_files"] = kinds["prompt"]
    measurements["scoped"]["skill_directories"] = len(
        {
            entry["path"].split("/")[2]
            for entry in files
            if entry["path"].lower().startswith(".github/skills/")
            and len(entry["path"].split("/")) > 2
        }
    )
    measurements["scoped"]["setup_workflows"] = kinds["setup"]
    measurements["scoped"]["mcp_files"] = kinds["mcp"]
    measurements["terraform_lock_files"] = kinds["terraform_lock"]
    if kinds["agents_guidance"] == 0:
        findings.append(
            finding(
                "A",
                "warning",
                "agents_guidance_missing",
                "Repository does not contain an AGENTS.md guidance file",
            )
        )
    if kinds["copilot_instructions"] == 0:
        findings.append(
            finding(
                "A",
                "warning",
                "copilot_instructions_missing",
                "Repository does not contain .github/copilot-instructions.md",
            )
        )

    for entry in relevant:
        path = entry["path"]
        kind = path_kind(path)
        raw_size = entry.get("size")
        if not isinstance(raw_size, int):
            result["errors"].append(
                {
                    "repository": record.name,
                    "operation": f"blob:{path}",
                    "kind": "size_unknown",
                    "message": "Relevant tree entry has no bounded blob size",
                }
            )
            continue
        size = raw_size
        measurements["config_bytes"] += size
        if size > THRESHOLDS["max_relevant_file_bytes"]:
            measurements["skipped_large_files"] += 1
            findings.append(
                finding(
                    "B",
                    "warning",
                    "relevant_file_too_large",
                    f"Relevant text file exceeds fetch bound: {size} bytes",
                    path=path,
                )
            )
            continue
        sha = entry.get("sha")
        if not isinstance(sha, str) or not sha:
            result["errors"].append(
                {
                    "repository": record.name,
                    "operation": "blob",
                    "kind": "malformed",
                    "message": f"Tree entry has no blob SHA: {path}",
                }
            )
            continue
        try:
            payload, _ = client.get_json(f"{repo_path}/git/blobs/{urllib.parse.quote(sha)}")
            text = decode_blob(payload, path)
        except InventoryFailure as exc:
            result["errors"].append(failure_record(record.name, f"blob:{path}", exc))
            continue
        measurements["fetched_files"] += 1
        line_count = len(text.splitlines())
        file_record: dict[str, Any] = {
            "path": path,
            "kind": kind,
            "bytes": len(text.encode("utf-8")),
            "lines": line_count,
        }
        if kind == "instruction":
            file_record.update(instruction_summary(text))
        elif kind == "agent":
            frontmatter, _, frontmatter_error = parse_frontmatter(text)
            file_record.update(
                {
                    "user_invocable": frontmatter.get("user-invocable"),
                    "disable_model_invocation": frontmatter.get(
                        "disable-model-invocation"
                    ),
                    "tools": normalized_tools(frontmatter.get("tools")),
                    "target": frontmatter.get("target"),
                    "frontmatter_error": frontmatter_error,
                }
            )
        elif kind == "setup":
            file_record.update(setup_summary(text))
        measurements["files"].append(file_record)
        measurements["config_lines"] += line_count
        if kind in {
            "agents_guidance",
            "copilot_instructions",
            "instruction",
            "agent",
            "prompt",
            "skill",
            "setup",
            "mcp",
        }:
            measurements["active_config_bytes"] += file_record["bytes"]
            measurements["active_config_lines"] += line_count
        if kind == "agents_guidance":
            measurements["core"]["agents"] = {
                "exists": True,
                "bytes": file_record["bytes"],
                "lines": line_count,
            }
        elif kind == "copilot_instructions":
            measurements["core"]["copilot_instructions"] = {
                "exists": True,
                "bytes": file_record["bytes"],
                "lines": line_count,
            }
        if kind in {"agents_guidance", "copilot_instructions"} or (
            kind == "instruction" and not file_record.get("manual")
        ):
            measurements["automatic_instruction_bytes"] += file_record["bytes"]
            measurements["automatic_instruction_lines"] += line_count
        if len(text.encode("utf-8")) > THRESHOLDS["max_relevant_file_bytes"]:
            findings.append(
                finding(
                    "B",
                    "error",
                    "blob_exceeded_declared_bound",
                    "Fetched blob exceeded the centralized relevant-file size bound",
                    path=path,
                )
            )
            continue
        measurements["scoped"]["mcp_servers"] += inspect_file_content(
            path,
            kind,
            text,
            findings,
            (item["path"] for item in files),
            approved_mcp=path.lower() in record.approved_mcp_paths,
        )
    core = measurements["core"]
    core["combined_bytes"] = (
        core["agents"]["bytes"] + core["copilot_instructions"]["bytes"]
    )
    core["combined_lines"] = (
        core["agents"]["lines"] + core["copilot_instructions"]["lines"]
    )
    broad_scopes = [
        file
        for file in measurements["files"]
        if file["kind"] == "instruction"
        and any(
            scope in {"*", "**", "**/*", "/**"} for scope in file.get("apply_to", [])
        )
    ]
    if len(broad_scopes) > 1:
        findings.append(
            finding(
                "F",
                "warning",
                "instruction_broad_scope_overlap",
                f"Repository contains {len(broad_scopes)} overlapping repository-wide automatic instructions",
            )
        )


def aggregate_totals(repositories: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    totals = {
        "repositories": 0,
        "inspected_repositories": 0,
        "tree_files": 0,
        "tree_bytes": 0,
        "config_bytes": 0,
        "config_lines": 0,
        "active_config_bytes": 0,
        "active_config_lines": 0,
        "automatic_instruction_bytes": 0,
        "automatic_instruction_lines": 0,
        "instruction_files": 0,
        "agent_files": 0,
        "prompt_files": 0,
        "skill_directories": 0,
        "setup_workflows": 0,
        "mcp_files": 0,
        "mcp_servers": 0,
        "terraform_lock_files": 0,
        "findings": {"info": 0, "warning": 0, "error": 0},
    }
    for repository in repositories:
        totals["repositories"] += 1
        if repository.get("metadata") is not None:
            totals["inspected_repositories"] += 1
        measurements = repository["measurements"]
        totals["tree_files"] += measurements["tree_files"]
        totals["tree_bytes"] += measurements["tree_bytes"]
        totals["config_bytes"] += measurements["config_bytes"]
        totals["config_lines"] += measurements["config_lines"]
        totals["active_config_bytes"] += measurements["active_config_bytes"]
        totals["active_config_lines"] += measurements["active_config_lines"]
        totals["automatic_instruction_bytes"] += measurements[
            "automatic_instruction_bytes"
        ]
        totals["automatic_instruction_lines"] += measurements[
            "automatic_instruction_lines"
        ]
        scoped = measurements["scoped"]
        for key in (
            "instruction_files",
            "agent_files",
            "prompt_files",
            "skill_directories",
            "setup_workflows",
            "mcp_files",
            "mcp_servers",
        ):
            totals[key] += scoped[key]
        totals["terraform_lock_files"] += measurements["terraform_lock_files"]
        for item in repository["findings"]:
            severity = item["severity"]
            totals["findings"][severity] = totals["findings"].get(severity, 0) + 1
    return totals


def compare_baseline(
    totals: Mapping[str, Any],
    baseline_path: Path | None,
    repositories: Iterable[Mapping[str, Any]] = (),
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if baseline_path is None:
        return (
            {
                "status": "first_run",
                "message": "No baseline was supplied; growth comparison was not performed.",
                "deltas": {},
                "threshold_exceeded": [],
                "repository_changes": [],
            },
            [],
        )
    try:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        return (
            {
                "status": "invalid_baseline",
                "message": redact(f"Baseline could not be loaded: {exc}"),
                "deltas": {},
                "threshold_exceeded": [],
                "repository_changes": [],
            },
            [
                finding(
                    "B",
                    "error",
                    "baseline_invalid",
                    f"Baseline could not be loaded: {exc}",
                    path=baseline_path.as_posix(),
                )
            ],
        )
    if not isinstance(baseline, dict) or baseline.get("schema_version") != SCHEMA_VERSION:
        return (
            {
                "status": "invalid_baseline",
                "message": "Baseline schema_version is incompatible.",
                "deltas": {},
                "threshold_exceeded": [],
                "repository_changes": [],
            },
            [
                finding(
                    "B",
                    "error",
                    "baseline_schema_incompatible",
                    f"Baseline must use schema_version {SCHEMA_VERSION}",
                    path=baseline_path.as_posix(),
                )
            ],
        )
    baseline_totals = baseline.get("totals")
    if not isinstance(baseline_totals, dict):
        return (
            {
                "status": "invalid_baseline",
                "message": "Baseline does not contain totals.",
                "deltas": {},
                "threshold_exceeded": [],
                "repository_changes": [],
            },
            [
                finding(
                    "B",
                    "error",
                    "baseline_totals_missing",
                    "Baseline does not contain a totals object",
                    path=baseline_path.as_posix(),
                )
            ],
        )
    metric_thresholds = {
        "repositories": "max_repository_growth",
        "active_config_bytes": "max_config_bytes_growth",
        "instruction_files": "max_instruction_file_growth",
        "agent_files": "max_agent_file_growth",
        "prompt_files": "max_prompt_file_growth",
        "skill_directories": "max_skill_file_growth",
        "mcp_servers": "max_mcp_server_growth",
    }
    deltas: dict[str, int] = {}
    exceeded: list[dict[str, Any]] = []
    for metric, threshold_key in metric_thresholds.items():
        current = int(totals.get(metric, 0))
        previous = int(baseline_totals.get(metric, 0))
        delta = current - previous
        deltas[metric] = delta
        if delta > THRESHOLDS[threshold_key]:
            exceeded.append(
                {
                    "metric": metric,
                    "delta": delta,
                    "threshold": THRESHOLDS[threshold_key],
                }
            )
    findings: list[dict[str, Any]] = []
    repository_changes: list[dict[str, Any]] = []
    baseline_repositories = {
        item.get("name"): item
        for item in baseline.get("repositories", [])
        if isinstance(item, dict) and isinstance(item.get("name"), str)
    }
    for repository in repositories:
        previous = baseline_repositories.get(repository.get("name"))
        if not previous:
            continue
        current_measurements = repository.get("measurements", {})
        previous_measurements = previous.get("measurements", {})
        changes: list[dict[str, Any]] = []
        for key, label in (
            ("agents", "AGENTS.md"),
            ("copilot_instructions", ".github/copilot-instructions.md"),
        ):
            current_bytes = int(
                current_measurements.get("core", {}).get(key, {}).get("bytes", 0)
            )
            previous_bytes = int(
                previous_measurements.get("core", {}).get(key, {}).get("bytes", 0)
            )
            delta = current_bytes - previous_bytes
            percent = (delta * 100 / previous_bytes) if previous_bytes > 0 else 0
            if (
                delta >= THRESHOLDS["core_file_growth_bytes"]
                and percent >= THRESHOLDS["core_file_growth_percent"]
            ):
                changes.append(
                    {
                        "metric": label,
                        "delta_bytes": delta,
                        "percent": round(percent, 1),
                    }
                )
                findings.append(
                    finding(
                        "B",
                        "warning",
                        "core_file_growth",
                        f"{label} grew by {delta} bytes ({percent:.1f}%)",
                        path=label,
                    )
                )
        current_auto = int(current_measurements.get("automatic_instruction_bytes", 0))
        previous_auto = int(previous_measurements.get("automatic_instruction_bytes", 0))
        auto_delta = current_auto - previous_auto
        auto_percent = (
            auto_delta * 100 / previous_auto if previous_auto > 0 else 0
        )
        if (
            auto_delta >= THRESHOLDS["automatic_instruction_growth_bytes"]
            and auto_percent >= THRESHOLDS["automatic_instruction_growth_percent"]
        ):
            changes.append(
                {
                    "metric": "automatic_instruction_bytes",
                    "delta_bytes": auto_delta,
                    "percent": round(auto_percent, 1),
                }
            )
            findings.append(
                finding(
                    "B",
                    "warning",
                    "automatic_instruction_growth",
                    f"Automatic instruction content grew by {auto_delta} bytes ({auto_percent:.1f}%)",
                )
            )
        current_scoped = current_measurements.get("scoped", {})
        previous_scoped = previous_measurements.get("scoped", {})
        for metric, code, label in (
            ("agent_files", "new_custom_agents", "custom agents"),
            ("setup_workflows", "new_setup_workflows", "Copilot setup workflows"),
            ("mcp_files", "new_mcp_files", "MCP files"),
        ):
            delta = int(current_scoped.get(metric, 0)) - int(
                previous_scoped.get(metric, 0)
            )
            if delta > 0:
                changes.append({"metric": metric, "delta": delta})
                findings.append(
                    finding(
                        "B",
                        "warning",
                        code,
                        f"Repository added {delta} {label}",
                    )
                )
        if changes:
            repository_changes.append(
                {"repository": repository.get("name"), "changes": changes}
            )
    status = (
        "investigation_required"
        if exceeded or repository_changes
        else "within_thresholds"
    )
    return (
        {
            "status": status,
            "message": (
                "Growth exceeds one or more investigation thresholds."
                if exceeded
                else "Growth is within centralized investigation thresholds."
            ),
            "deltas": deltas,
            "threshold_exceeded": exceeded,
            "repository_changes": repository_changes,
        },
        findings,
    )


def overall_result(has_errors: bool, incomplete: bool, warnings: bool) -> tuple[str, int]:
    if has_errors and incomplete:
        return "errors_and_incomplete", 3
    if incomplete:
        return "incomplete", 2
    if has_errors:
        return "errors", 1
    if warnings:
        return "warnings", 0
    return "pass", 0


def build_report(
    records: list[CatalogRecord],
    catalog_findings: list[dict[str, Any]],
    duplicates: list[str],
    repositories: list[dict[str, Any]],
    *,
    owner: str,
    catalog_root: Path,
    fixture: Path | None,
    baseline: Path | None,
    client: GitHubClient,
) -> dict[str, Any]:
    totals = aggregate_totals(repositories)
    growth, baseline_findings = compare_baseline(totals, baseline, repositories)
    global_findings = catalog_findings + baseline_findings
    for item in global_findings:
        totals["findings"][item["severity"]] = (
            totals["findings"].get(item["severity"], 0) + 1
        )
    errors = [
        error
        for repository in repositories
        for error in repository["errors"]
    ]
    incomplete = any(repository["incomplete"] for repository in repositories)
    has_errors = totals["findings"].get("error", 0) > 0
    warnings = totals["findings"].get("warning", 0) > 0
    result, exit_code = overall_result(has_errors, incomplete, warnings)
    classifications = Counter(repository["classification"] for repository in repositories)
    exceptions = [
        {
            "repository": record.name,
            "classification": record.classification,
            "review_governance": record.review_governance,
            "reason": record.reason,
        }
        for record in records
        if record.classification in {"empty", "excluded", "decommissioned"}
        or record.review_governance == "exempt"
    ]
    return {
        "schema_version": SCHEMA_VERSION,
        "inventory_version": INVENTORY_VERSION,
        "generated_at": utc_timestamp(),
        "source": {
            "owner": owner,
            "catalog_root": catalog_root.as_posix(),
            "fixture": fixture.as_posix() if fixture else None,
            "baseline": baseline.as_posix() if baseline else None,
        },
        "manual_controls": [
            {
                "id": "COP-313",
                "status": "manual",
                "note": MANUAL_CONTROL_NOTE,
            }
        ],
        "checks": CHECKS,
        "thresholds": THRESHOLDS,
        "catalog": {
            "records": len(records),
            "duplicates": duplicates,
            "findings": global_findings,
        },
        "classifications": dict(sorted(classifications.items())),
        "totals": totals,
        "repositories": repositories,
        "exceptions": exceptions,
        "growth": growth,
        "rate_limit": client.rate_limit,
        "errors": errors,
        "incomplete": incomplete,
        "overall": {
            "result": result,
            "has_errors": has_errors,
            "incomplete": incomplete,
            "exit_code": exit_code,
        },
    }


def markdown_report(report: Mapping[str, Any]) -> str:
    overall = report["overall"]
    totals = report["totals"]
    lines = [
        "# Copilot estate inventory",
        "",
        f"- **Result:** `{overall['result']}`",
        f"- **Generated:** {report['generated_at']}",
        f"- **Schema:** `{report['schema_version']}`",
        f"- **Inventory:** `{report['inventory_version']}`",
        f"- **Repositories:** {totals['repositories']} cataloged; "
        f"{totals['inspected_repositories']} metadata-inspected",
        f"- **Findings:** {totals['findings'].get('error', 0)} errors, "
        f"{totals['findings'].get('warning', 0)} warnings",
        f"- **Incomplete:** {'yes' if report['incomplete'] else 'no'}",
        f"- **Growth:** `{report['growth']['status']}`",
        f"- **Active configuration:** {totals['active_config_bytes']} bytes / "
        f"{totals['active_config_lines']} lines",
        "",
        f"> {MANUAL_CONTROL_NOTE}",
        "",
        "## Classifications",
        "",
        "| Classification | Count |",
        "| --- | ---: |",
    ]
    for classification, count in report["classifications"].items():
        lines.append(f"| {classification} | {count} |")
    lines.extend(
        [
            "",
            "## Repository results",
            "",
            "| Repository | Classification | Review | Errors | Warnings | Incomplete |",
            "| --- | --- | --- | ---: | ---: | --- |",
        ]
    )
    for repository in report["repositories"]:
        counts = Counter(item["severity"] for item in repository["findings"])
        lines.append(
            f"| `{repository['name']}` | {repository['classification']} | "
            f"{repository['review_governance']} | {counts['error']} | "
            f"{counts['warning']} | {'yes' if repository['incomplete'] else 'no'} |"
        )
    all_findings = list(report["catalog"]["findings"]) + [
        {**item, "repository": repository["name"]}
        for repository in report["repositories"]
        for item in repository["findings"]
    ]
    if all_findings:
        lines.extend(["", "## Findings", ""])
        for item in all_findings:
            location = item.get("repository") or item.get("path") or "catalog"
            path = item.get("path")
            line = item.get("line")
            path_detail = (
                f" `{path}{':' + str(line) if line else ''}`" if path else ""
            )
            evidence = f" — `{item['evidence']}`" if item.get("evidence") else ""
            lines.append(
                f"- **{item['severity'].upper()} {item['check']}/{item['code']}** "
                f"({location}){path_detail}: {item['message']}{evidence}"
            )
    if report["errors"]:
        lines.extend(["", "## Incomplete operations", ""])
        for error in report["errors"]:
            lines.append(
                f"- `{error['repository']}` {error['operation']}: "
                f"{error['kind']} — {error['message']}"
            )
    lines.extend(["", "## Growth", "", report["growth"]["message"], ""])
    return "\n".join(lines)


def summary_markdown(report: Mapping[str, Any]) -> str:
    totals = report["totals"]
    return "\n".join(
        [
            "## Copilot estate inventory",
            "",
            f"Result: **{report['overall']['result']}**  ",
            f"Repositories: **{totals['repositories']}**  ",
            f"Errors: **{totals['findings'].get('error', 0)}**; "
            f"warnings: **{totals['findings'].get('warning', 0)}**  ",
            f"Incomplete: **{'yes' if report['incomplete'] else 'no'}**  ",
            f"Growth: **{report['growth']['status']}**",
            "",
            MANUAL_CONTROL_NOTE,
            "",
        ]
    )


def validate_report_schema(report: Mapping[str, Any]) -> None:
    required = {
        "schema_version": str,
        "inventory_version": str,
        "generated_at": str,
        "source": dict,
        "manual_controls": list,
        "checks": dict,
        "thresholds": dict,
        "catalog": dict,
        "classifications": dict,
        "totals": dict,
        "repositories": list,
        "exceptions": list,
        "growth": dict,
        "rate_limit": dict,
        "errors": list,
        "incomplete": bool,
        "overall": dict,
    }
    for key, expected_type in required.items():
        if key not in report or not isinstance(report[key], expected_type):
            raise ValueError(
                f"Report schema {SCHEMA_VERSION} requires {key} as "
                f"{expected_type.__name__}"
            )
    if report["schema_version"] != SCHEMA_VERSION:
        raise ValueError(f"Unsupported report schema: {report['schema_version']}")
    for repository in report["repositories"]:
        if not isinstance(repository, dict) or not {
            "name",
            "classification",
            "measurements",
            "findings",
            "errors",
        }.issubset(repository):
            raise ValueError("Report repository entry is missing required fields")


def write_reports(report: Mapping[str, Any], output_dir: Path) -> None:
    validate_report_schema(report)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / REPORT_JSON).write_text(
        json.dumps(report, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )
    (output_dir / REPORT_MARKDOWN).write_text(
        markdown_report(report), encoding="utf-8"
    )
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with Path(summary_path).open("a", encoding="utf-8") as summary:
            summary.write(summary_markdown(report))


def load_fixture(path: Path | None) -> tuple[FixtureTransport | None, Any]:
    if path is None:
        return None, None
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or not isinstance(payload.get("responses"), dict):
        raise ValueError("Fixture must be an object containing a responses object")
    records = payload.get("catalog_records")
    if records is not None and not isinstance(records, list):
        raise ValueError("Fixture catalog_records must be a list")
    return FixtureTransport(payload["responses"]), records


def run_inventory(
    *,
    catalog_root: Path,
    owner: str,
    token: str | None,
    output_dir: Path,
    baseline: Path | None = None,
    fixture: Path | None = None,
    transport: Transport | None = None,
) -> tuple[dict[str, Any], int]:
    fixture_transport, fixture_records = load_fixture(fixture)
    client = GitHubClient(token, transport=transport or fixture_transport)
    records, catalog_findings, duplicates = load_catalog(
        catalog_root, fixture_records
    )
    repositories: list[dict[str, Any]] = []
    duplicate_names = {name.casefold() for name in duplicates}
    for record in records:
        if record.name.casefold() in duplicate_names:
            repositories.append(
                {
                    "name": record.name,
                    "catalog_path": record.path,
                    "classification": "unknown/inconsistent",
                    "inspection": "none",
                    "review_governance": record.review_governance,
                    "reason": record.reason or None,
                    "metadata": None,
                    "measurements": empty_measurements(),
                    "ruleset": None,
                    "findings": [],
                    "errors": [],
                    "incomplete": False,
                }
            )
            continue
        repositories.append(inspect_repository(record, owner, client))
    report = build_report(
        records,
        catalog_findings,
        duplicates,
        repositories,
        owner=owner,
        catalog_root=catalog_root,
        fixture=fixture,
        baseline=baseline,
        client=client,
    )
    write_reports(report, output_dir)
    return report, int(report["overall"]["exit_code"])


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Read-only GitHub Copilot estate inventory for workload catalog repositories"
    )
    parser.add_argument(
        "--catalog-root",
        type=Path,
        default=Path("terraform/workloads"),
        help="Catalog root containing JSON records (examples is excluded)",
    )
    parser.add_argument("--owner", default=DEFAULT_OWNER, help="GitHub repository owner")
    parser.add_argument(
        "--token-env",
        default="GITHUB_TOKEN",
        help="Environment variable containing the GitHub read token",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("artifacts/copilot-estate-inventory"),
        help="Directory for JSON and Markdown reports",
    )
    parser.add_argument(
        "--baseline", type=Path, help="Optional prior JSON report for growth comparison"
    )
    parser.add_argument(
        "--fixture",
        type=Path,
        help="Offline response fixture; fixture catalog_records override catalog discovery",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    token = os.environ.get(args.token_env)
    try:
        report, exit_code = run_inventory(
            catalog_root=args.catalog_root,
            owner=args.owner,
            token=token,
            output_dir=args.output_dir,
            baseline=args.baseline,
            fixture=args.fixture,
        )
    except Exception as exc:
        # Even startup/configuration failures produce stable reports before exit.
        client = GitHubClient(None, transport=FixtureTransport({}))
        startup_finding = finding(
            "B", "error", "inventory_startup_failure", f"Inventory could not start: {exc}"
        )
        report = build_report(
            [],
            [startup_finding],
            [],
            [],
            owner=args.owner,
            catalog_root=args.catalog_root,
            fixture=args.fixture,
            baseline=None,
            client=client,
        )
        write_reports(report, args.output_dir)
        exit_code = 1
    print(
        f"Copilot estate inventory: {report['overall']['result']} "
        f"(errors={report['totals']['findings'].get('error', 0)}, "
        f"warnings={report['totals']['findings'].get('warning', 0)}, "
        f"incomplete={str(report['incomplete']).lower()})"
    )
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
