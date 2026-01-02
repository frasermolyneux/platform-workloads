---
name: "Align platform-workloads consumers"
description: "Find projects consuming platform-workloads remote-state outputs and align them to the documented pattern."
argument-hint: "Optional: workspace root to scope searches"
agent: "default"
model: "gpt-5.1-codex-max"
tools: ["file_search", "read_file", "apply_patch", "run_in_terminal"]
---

Intent: In VS Code, discover all workspace projects that ingest platform-workloads outputs (resource groups, Terraform backends, administrative units) and refactor them to match the pattern in [docs/consuming-platform-workloads-outputs.md](../../docs/consuming-platform-workloads-outputs.md).

Inputs:
- {{workspaceRoot}} — root folder to scan; default to current workspace.
- {{patternTargets}} — optional glob(s) to narrow search (e.g., `platform-*/terraform/**`).

Guardrails:
1. Use `#tool:file_search` and `#tool:read_file` to locate `terraform_remote_state` usage and lookups of `workload_resource_groups`, `workload_terraform_backends`, or `workload_administrative_units`; prefer globs like `**/terraform/**`. 
2. Conform to the documented pattern in [docs/consuming-platform-workloads-outputs.md](../../docs/consuming-platform-workloads-outputs.md); keep environment keys in tag form (`dev`/`tst`/`prd`) and normalize locations to lowercase.
3. Shell is `pwsh.exe`; forbid destructive commands (`git reset --hard`, `git clean -fd`); if formatting is needed, run only targeted `terraform fmt` under the changed module via `#tool:run_in_terminal`.
4. Reference repo-wide rules in [../copilot-instructions.md](../copilot-instructions.md) and the VS Code prompt guidance from the [official docs](https://code.visualstudio.com/docs/copilot/customization/prompt-files); respect workspace settings.
5. Keep changes ASCII and minimal; prefer `#tool:apply_patch` for edits and avoid touching generated files.

Workflow (example):
```powershell
# scan for remote state usage
#tool:file_search --query "terraform_remote_state" --includePattern "${input:patternTargets}" 

# inspect candidates
#tool:read_file --filePath "<path>" --startLine 1 --endLine 200

# patch to align with docs
#tool:apply_patch --input "..."
```

Validation:
- Summarize changed files and how they now match [docs/consuming-platform-workloads-outputs.md](../../docs/consuming-platform-workloads-outputs.md).
- If Terraform files changed, suggest running `terraform fmt` in the affected module (do not run globally unless requested).
- Confirm no destructive commands were executed.

Checklist:
- [ ] Located all consumers of platform-workloads outputs.
- [ ] Environment tags and location keys match the documented shape.
- [ ] Optional outputs (backends, AUs) guarded with `try`/null checks.
- [ ] Changes summarized and validation guidance provided.