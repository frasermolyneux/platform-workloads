# Platform Workloads - Copilot Instructions

## Architecture Overview

This repository manages Azure infrastructure and CI/CD configurations for multiple workloads using a **declarative JSON-driven Terraform approach**. Workload definitions in `terraform/workloads/` drive the creation of:

- **Azure AD** service principals with federated credentials (OIDC)
- **GitHub** repositories with environment configurations
- **Azure DevOps** projects, service connections, and variable groups
- **Azure RBAC** role assignments at subscription/resource scopes
- **Terraform state storage** (when `configure_for_terraform: true`)

The core pattern: JSON workload files → Terraform reads via `fileset()` → generates all infrastructure.

## Workload Definition Structure

Workload JSON files (`terraform/workloads/**/*.json`) define everything. Key patterns:

```json
{
  "name": "workload-name",
  "github": { 
    "description": "...", 
    "topics": [...],
    "visibility": "public|private"
  },
  "environments": [
    {
      "name": "Development|Production",
      "subscription": "sub-alias",
      "devops_project": "ProjectName",
      "connect_to_github": true,
      "connect_to_devops": true,
      "configure_for_terraform": true,
      "add_deploy_script_identity": true,
      "role_assignments": [
        {
          "scope": "sub-alias or full ARM resource ID",
          "role_definitions": ["Contributor", "Key Vault Secrets Officer"]
        }
      ],
      "directory_roles": ["Cloud application administrator"]
    }
  ]
}
```

**Important**: Files in `terraform/workloads/examples/` are excluded via `workloads.load.tf` logic.

## Critical Patterns

### 1. Service Principal Naming
Format: `spn-{workload-name}-{environment-name}` (lowercase). Created per environment in [azure-workloads.tf](../terraform/azure-workloads.tf).

### 2. OIDC Federation
- **GitHub**: Subject `repo:frasermolyneux/{repo}:environment:{Environment}` ([azure-workloads.if-github.tf](../terraform/azure-workloads.if-github.tf))
- **Azure DevOps**: Dynamic issuer/subject from service endpoint ([azure-workloads.if-devops.tf](../terraform/azure-workloads.if-devops.tf))

### 3. Role Assignment Scopes
Handles both subscription aliases and full ARM resource IDs. See [azure-workloads.role-assignments.tf](../terraform/azure-workloads.role-assignments.tf) for scope resolution logic using `data.azurerm_subscription.subscriptions`.

### 4. Terraform State Management
When `configure_for_terraform: true`, creates resource group `rg-tf-{workload}-{env}-{location}-{instance}` with storage account for remote state ([azure-workloads.if-terraform.tf](../terraform/azure-workloads.if-terraform.tf)).

## Common Tasks

### Adding a New Workload
1. Create JSON file in `terraform/workloads/{category}/`
2. Define `name`, `github`, and `environments` sections
3. Terraform automatically picks it up via `fileset()` in [workloads.load.tf](../terraform/workloads.load.tf)
4. Run `terraform plan` to preview changes

### Modifying Role Assignments
Edit `role_assignments` array in workload JSON. Each assignment:
- `scope`: Subscription alias (e.g., `"sub-platform-strategic"`) or full ARM resource ID
- `role_definitions`: Array of role names (not GUIDs)

Both service principal AND deploy script identity (if enabled) get the roles.

### Running Terraform
Production workflow uses:
```bash
terraform plan -var-file="tfvars/prd.tfvars" -backend-config="backends/prd.backend.hcl"
```

Requires environment variables:
- `AZDO_PERSONAL_ACCESS_TOKEN` (Azure DevOps PAT)
- `GITHUB_TOKEN` (GitHub provider authentication)

## Key Files

- [workloads.load.tf](../terraform/workloads.load.tf): Discovers all workload JSON files
- [azure-workloads.tf](../terraform/azure-workloads.tf): GitHub repos, environments, app registrations
- [azure-workloads.rbac.tf](../terraform/azure-workloads.rbac.tf): Complex RBAC administrator mappings
- [locals.tf](../terraform/locals.tf): Resource naming conventions
- [variables.tf](../terraform/variables.tf): `subscriptions` map and `environment_map` (Dev→dev, Prod→prd)

## Conventions

- **Subscription aliases**: Use short names like `sub-visualstudio-enterprise` mapped in `tfvars/prd.tfvars`
- **Tenant ID**: Hard-coded `e56a6947-bb9a-4a6e-846a-1f118d1c3a14` across multiple files
- **Resource naming**: `{type}-{workload}-{env}-{location}-{instance}` format
- **Terraform formatting**: Run `terraform fmt` before commits (see terminal history)
- **Environment mapping**: Development→dev, Testing→tst, Production→prd

## Gotchas

1. **Service principal must be Owner at `/` scope** for creating role assignments across subscriptions
2. **Workload JSON changes are immediate** - no staging/preview step beyond `terraform plan`
3. **Deploy script identity** requires `add_deploy_script_identity: true` AND role assignments
4. **Examples folder exclusion**: `workloads/examples/` files intentionally ignored by `!startswith(file_path, "examples/")`
