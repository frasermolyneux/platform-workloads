# Platform Workloads - Copilot Instructions

## Core Model
- Declarative, JSON-driven Terraform: workload files under [terraform/workloads](../terraform/workloads) (excluding examples/) are discovered in [terraform/workloads.load.tf](../terraform/workloads.load.tf) and flattened into `{workload}-{environment}` keys consumed across the `azure-workloads.*.tf` stack.
- Outputs per workload/environment: GitHub repo + environments, Azure AD app/SPN with OIDC, Azure DevOps project integrations, RBAC role assignments, optional Terraform state RG/SA/container.
- Reader auto-injection: if no subscription-level assignment exists for an environment, a Reader role is added/merged for that subscription in [terraform/azure-workloads.tf](../terraform/azure-workloads.tf) locals.

## Workload JSON Shape
- Minimal fields: `name`, `github` (description/topics/visibility), `environments` array with `name`, `subscription`, optional `devops_project`, `connect_to_github`, `connect_to_devops`, `configure_for_terraform`, `add_deploy_script_identity`.
- Role inputs live under `role_assignments.assigned_roles[*]` (scope + roles array) and `role_assignments.rbac_admin_roles[*]` (allowed_roles). Directory roles, resource_groups, locations, and `requires_terraform_state_access` are optional extensions.
- Scope inputs accept: subscription alias (`var.subscriptions`), full ARM ID, `sub:alias`, `workload:workload/environment`, or `workload-rg:workload/environment` helpers resolved in [terraform/azure-workloads.role-assignments.tf](../terraform/azure-workloads.role-assignments.tf).

## Naming, Defaults, Guards
- SPN/app naming: `spn-{workload}-{environment}` (lowercase) created in [terraform/azure-workloads.tf](../terraform/azure-workloads.tf); resource naming convention `{type}-{workload}-{env}-{location}-{instance}` with environment map Development→dev, Testing→tst, Production→prd ([terraform/variables.tf](../terraform/variables.tf)).
- Tenant ID is fixed to `e56a6947-bb9a-4a6e-846a-1f118d1c3a14`; default location `uksouth` and instance `01` from vars.
- Examples in `terraform/workloads/examples/` are intentionally ignored—real workloads live under platform/, portal/, geo-location/, etc.

## OIDC & Integrations
- GitHub federation subject: `repo:frasermolyneux/{repo}:environment:{Environment}`; environment variables `AZURE_CLIENT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID` published per environment in [terraform/azure-workloads.if-github.tf](../terraform/azure-workloads.if-github.tf).
- Azure DevOps federation issuer/subject come from the generated service endpoint; variable groups per environment expose the same Azure identifiers and Terraform backend details when `configure_for_terraform` is true ([terraform/azure-workloads.if-devops.tf](../terraform/azure-workloads.if-devops.tf)).

## Terraform State Path
- When `configure_for_terraform` is true, [terraform/azure-workloads.if-terraform.tf](../terraform/azure-workloads.if-terraform.tf) creates `rg-tf-{workload}-{env}-{location}-{instance}` + storage account + `tfstate` container, assigning the SPN `Storage Account Key Operator`, `Storage Blob Data Contributor`, and `Reader` on the account.
- `requires_terraform_state_access` lets one workload read another's state (grants Storage Blob Data Reader on the target storage account).

## RBAC Expansion & Delegation
- Assigned roles are expanded per role name and resolved scope; deploy script identity (if enabled) receives the same set in [terraform/azure-workloads.role-assignments.tf](../terraform/azure-workloads.role-assignments.tf).
- Conditional RBAC administration uses `Role Based Access Control Administrator` with ABAC conditions limiting allowed role IDs derived from `rbac_admin_roles` in [terraform/azure-workloads.rbac.tf](../terraform/azure-workloads.rbac.tf).

## Working Locally
- From [terraform](../terraform): `terraform init -backend-config="backends/prd.backend.hcl"`; `terraform plan -var-file="tfvars/prd.tfvars"`; include `-var "github_service_connection_pat=$env:AZDO_GITHUB_SERVICE_CONNECTION_PAT"` when needed.
- Common env vars: `AZDO_PERSONAL_ACCESS_TOKEN`, `GITHUB_TOKEN`, optional `AZDO_GITHUB_SERVICE_CONNECTION_PAT` for DevOps GitHub service connections.
- Targeting examples: `terraform plan -var-file="tfvars/prd.tfvars" -target="github_repository.workload[\"portal-core\"]"`.

## Quick Pointers
- Add a workload by dropping JSON under `terraform/workloads/{category}/`; discovery is automatic via `fileset()`.
- Service principal executing Terraform needs Owner at `/` to create cross-subscription assignments.
- Docs: [docs/architecture.md](../docs/architecture.md), [docs/workload-configuration.md](../docs/workload-configuration.md), [docs/developer-guide.md](../docs/developer-guide.md), [docs/prerequisites.md](../docs/prerequisites.md).
