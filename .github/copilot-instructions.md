# Copilot Instructions

## Project Overview

This is a Terraform stack that transforms JSON workload definitions into Azure AD applications, service principals with OIDC federation, GitHub repositories with environments and secrets, Azure DevOps service connections/environments/variable groups, and workload-scoped RBAC role assignments. It is an infrastructure-as-code project using HCL (Terraform) with JSON configuration files.

## Repository Structure

- `terraform/` — All Terraform configuration files (`.tf`) and workload definitions.
- `terraform/workloads/` — JSON workload definition files organized by category. Files under `examples/` are excluded.
- `terraform/workloads.load.tf` — Discovers and loads all workload JSON files, flattening them to `{workload}-{environment}` keys.
- `terraform/azure-workloads.tf` — Core resource definitions for Azure AD apps, service principals, and GitHub repositories.
- `terraform/azure-workloads.if-*.tf` — Feature-gated resources toggled by `connect_to_github`, `connect_to_devops`, `configure_for_terraform`, and `add_deploy_script_identity`.
- `terraform/azure-workloads.rbac.tf` — ABAC-conditioned RBAC admin delegation using allowed role lists.
- `.github/workflows/` — CI/CD workflows for PR verification, deployments, code quality, and Dependabot automerge.
- `docs/` — Architecture, workload configuration schema, developer guide, prerequisites, role assignments, and output consumption guides.

## Key Conventions

- **Naming**: Service principals follow `spn-{workload}-{environment}` (lowercase). Environments map via `var.environment_map` (Development→dev, Testing→tst, Production→prd).
- **Scope resolution**: Supports subscription aliases from `var.subscriptions`, raw ARM IDs, and `workload:`/`workload-rg:` helpers. Reader role is auto-added per environment subscription.
- **OIDC subjects**: GitHub uses `repo:frasermolyneux/{repo}:environment:{Environment}`. Always prefer OIDC over client secrets.
- **State sharing**: When `configure_for_terraform` is true, per-workload RG/storage/container is created and exposed via outputs; downstream consumers use `use_oidc = true`.
- **Formatting**: Always run `terraform fmt -recursive` before committing changes.

## Working with This Codebase

- Run `cd terraform` then `terraform init -backend-config="backends/prd.backend.hcl"` to initialize.
- Use `terraform plan -var-file="tfvars/prd.tfvars"` to preview changes; use `-target` for scoped plans.
- To add a workload, create a JSON file under `terraform/workloads/{category}/`. Validate with `terraform plan`. Ensure subscriptions referenced in JSON exist in the `tfvars` alias map.
- Provider authentication requires Azure CLI login with Owner at `/`, plus `AZDO_PERSONAL_ACCESS_TOKEN`, `GITHUB_TOKEN`, and optionally `AZDO_GITHUB_SERVICE_CONNECTION_PAT` environment variables.

## Providers

The stack uses `azurerm`, `azapi`, `azuredevops`, and `github` Terraform providers. See `terraform/providers.tf` for version constraints.

## Documentation

Refer to [docs/architecture.md](docs/architecture.md), [docs/workload-configuration.md](docs/workload-configuration.md), [docs/developer-guide.md](docs/developer-guide.md), [docs/prerequisites.md](docs/prerequisites.md), [docs/role-assignments.md](docs/role-assignments.md), and [docs/consuming-platform-workloads-outputs.md](docs/consuming-platform-workloads-outputs.md) for detailed guidance.

## Troubleshooting

- Scope resolution errors typically indicate alias/ARM ID mismatches in workload JSON.
- Permission failures usually mean the executing identity lacks Owner at root scope (`/`).
- Federation errors suggest missing GitHub or Azure DevOps OIDC subjects.
- Terraform state access requires Storage Account Key Operator Service Role, Storage Blob Data Contributor, and Reader when state storage is enabled.
