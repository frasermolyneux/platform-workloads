# AGENTS.md - platform-workloads

This production-only Terraform repository converts workload and repository-governance JSON into Azure identity, GitHub, Cloudflare, RBAC, and optional workload state infrastructure. It is the source of remote-state outputs consumed by other platform repositories.

## Key locations

- `terraform/workloads/` - workload and repository-governance catalog; `examples/` is excluded.
- `terraform/workloads.load.tf` - JSON discovery and normalization.
- `terraform/azure-workloads*.tf` - identities, repositories, integrations, state, and RBAC.
- `terraform/azure-workloads.rulesets.tf` - central repository review-governance implementation.
- `terraform/azure-workloads.repository-analysis.tf` - validated scoped source policy and lifecycle-safe GitHub analysis variables.
- `terraform/providers.tf` - reviewed provider compatibility boundary.
- `docs/` - architecture, schema, operations, output consumption, and decommissioning.

## Validation

For documentation or Copilot-configuration-only changes:

```pwsh
git diff --check
```

For Terraform changes:

```pwsh
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false -upgrade
terraform -chdir=terraform validate
terraform -chdir=terraform test '-var-file=tfvars\prd.tfvars' '-filter=tests\repository-analysis.tftest.hcl'
```

Run the production state-backed plan only for infrastructure-affecting changes:

```pwsh
terraform -chdir=terraform init -reconfigure -backend-config=backends/prd.backend.hcl
terraform -chdir=terraform plan -var-file=tfvars/prd.tfvars
```

## Guardrails

- Preserve the existing provider constraints and repository-governance behavior.
- Do not edit workload or governance JSON for unrelated tasks.
- Do not manually edit GitHub rulesets that this stack owns.
- Preserve OIDC subjects, remote-state outputs, scope helpers, and state addresses.
- Follow the documented state-first decommissioning sequence before deleting workload JSON.
- Never add client secrets or credentials.
- `.terraform.lock.hcl` is generated locally, ignored, and not committed.
- Non-`xi-*` catalog rows require an analysis profile or explicit exemption; private source must never select public Sonar execution.
- Analysis contract tests target only built-in metadata and need no provider reads. Production plans/applies must still cover the complete configuration.
- Do not cancel running stateful plans/applies. Recover only a confirmed orphaned state-lock ID with explicit operator approval.

See [docs/architecture.md](docs/architecture.md), [docs/workload-configuration.md](docs/workload-configuration.md), [docs/developer-guide.md](docs/developer-guide.md), and [docs/decommissioning.md](docs/decommissioning.md).
