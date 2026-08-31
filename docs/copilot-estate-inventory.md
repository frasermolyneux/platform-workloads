# Copilot estate inventory

`scripts/copilot_estate_inventory.py` performs the read-only COP-315 inventory
of repositories listed by `terraform/workloads/**/*.json`, excluding
`examples/`. The workload catalog remains the sole repository list. The script
does not remediate repositories, mutate GitHub, run Terraform, or verify
controls outside documented GitHub REST responses.

## Classification and exceptions

Catalog records are active, repository-inspected, and review-governed by
default. Add `github.inventory` only when an explicit exception is required:

- `active` / `repository` can inspect repository-native configuration, with
  `review_governance` set to `required` or `exempt`;
- `empty` / `metadata` verifies metadata only and requires no review rule;
- `excluded` / `none` is never queried;
- `decommissioned` / `none` is ignored and never queried.

Every non-default state needs a clear `reason`. Private repositories must be
excluded. Archived or disabled repositories are classified from GitHub
metadata and receive metadata-only results. Duplicates, contradictory catalog
settings, newly discovered empty repositories, and private inspection targets
are inconsistent.

An approved repository MCP exception must be explicit in
`github.inventory.approved_mcp_paths` and retain the catalog `reason`; no
exceptions are currently configured.

Add or remove repository scope through the workload catalog and the normal
review process; do not maintain a separate inventory list.

## Read-only collection

The client structurally issues `GET` requests only, with a descriptive user
agent, the `2022-11-28` API version, a timeout, pagination, bounded transient
retries, and rate-limit capture. It reads:

1. repository metadata;
2. the recursive tree for the default branch;
3. bounded, relevant UTF-8 blobs by tree SHA;
4. the repository ruleset list with `includes_parents=false`;
5. every listed ruleset detail.

Excluded and decommissioned records are never queried. A repository failure
does not stop later repositories. Authentication, secret references, token
values, and signed URL query values are redacted from reports.

The workflow token is `secrets.TERRAFORM_GITHUB_TOKEN`, mapped to
`GITHUB_TOKEN`. It needs read access to public repository metadata, contents,
and repository rulesets for the cataloged owner. The workflow itself grants
only `contents: read`.

## Checks and severity

Checks A-J cover:

- core `AGENTS.md` and Copilot instruction byte/line measurements;
- scoped instructions, agents, prompts, skills, setup workflows, and known MCP
  paths;
- tracked `.terraform.lock.hcl` files anywhere in a repository;
- active legacy shared-catalog checkouts or references, while suppressing
  historical and prohibitive documentation;
- mandatory or repeated review loops;
- simple instruction/agent YAML frontmatter, missing or broad `applyTo`;
- custom-agent model invocation, user invocation, target, tools, and
  delegation;
- Copilot setup workflow versions, permissions, job shape, warning-level
  build/test/format/pack/browser operations, and prohibited plan/apply or
  deployment/publication commands;
- MCP JSON shape and server counts;
- exactly one governed `copilot_code_review` rule, with
  `review_draft_pull_requests=false` and `review_on_push=false`.

Errors fail the audit. Warnings identify missing guidance, broad scope, old
setup action majors, and threshold investigation without failing it. API,
rate-limit, malformed-response, truncated-tree, and access failures make the
inventory incomplete.

COP-313 is a **manual control—not API verified**. Code-review MCP access is
externally confirmed disabled, but the GitHub settings toggle lacks a suitable
documented estate read API. The inventory does not scrape settings pages.

## Run locally

```pwsh
$env:GITHUB_TOKEN = $env:TERRAFORM_GITHUB_TOKEN
python scripts/copilot_estate_inventory.py `
  --catalog-root terraform/workloads `
  --owner frasermolyneux `
  --output-dir artifacts/copilot-estate-inventory
```

An offline smoke run needs no token:

```pwsh
python scripts/copilot_estate_inventory.py `
  --owner fixture `
  --fixture tests/fixtures/copilot-estate-dry-run.json `
  --output-dir artifacts/copilot-estate-dry-run
```

Use `--token-env NAME` to select another environment variable. Use
`--baseline path/to/copilot-estate-inventory.json` to compare stable total
metrics with a prior report.

Reports are always attempted before exit:

- `copilot-estate-inventory.json` uses stable `schema_version: "1.0"`;
- `copilot-estate-inventory.md` is the investigation view;
- `GITHUB_STEP_SUMMARY` receives a concise result when available.

The workflow artifact name is `copilot-estate-inventory`.

Exit `0` means pass or warnings, `1` means findings contain errors, `2` means
collection is incomplete, and `3` deterministically means both errors and
incomplete collection.

## Growth and investigation

The first run records `growth.status: first_run`. With `--baseline`, stable
totals are compared with centralized thresholds in the script. Exceeded
thresholds request investigation but do not fail the audit. Confirm that
growth is legitimate, retain the new report as the next baseline if
appropriate, or deliberately update the centralized threshold with review.
Do not use the inventory to perform remediation.

The weekly/manual
`.github/workflows/copilot-estate-inventory.yml` runs unit tests before live
collection, uploads JSON and Markdown for 30 days even when the audit fails,
writes the step summary, and then preserves the inventory exit code.
