# Developer Guide

## Prerequisites

- Terraform >= 1.14.0
- Azure CLI with authenticated session
- PATs: Azure DevOps (`AZDO_PERSONAL_ACCESS_TOKEN`) and GitHub (`GITHUB_TOKEN`)

## Authentication Setup

#### Azure Authentication

```bash
# Login to Azure
az login

# Set active subscription
az account set --subscription "<subscription-id>"
```

#### Environment Variables

Required for running Terraform:

```powershell
# Azure DevOps PAT for provider authentication
$env:AZDO_PERSONAL_ACCESS_TOKEN = "<your-pat>"

# GitHub PAT for provider authentication
$env:GITHUB_TOKEN = "<your-github-pat>"
```

## Terraform Workflow

```bash
cd terraform
terraform init -backend-config="backends/prd.backend.hcl"
terraform plan -var-file="tfvars/prd.tfvars" -var="github_service_connection_pat=$env:AZDO_GITHUB_SERVICE_CONNECTION_PAT"
terraform fmt -recursive  # Before committing
```

## Workload Patterns

### JSON Discovery Mechanism

Workloads are auto-discovered via `fileset()` in `workloads.load.tf`:
- Files in `workloads/examples/` are excluded
- Changes take effect on next `terraform plan/apply`
- No Terraform code changes needed for new workloads

### Testing New Workloads

```bash
# Validate JSON syntax
Get-Content terraform/workloads/platform/new-workload.json | ConvertFrom-Json

# Preview Terraform changes
terraform plan -target='github_repository.workload["new-workload"]'
```

## Common Issues

### Service Principal Permissions

Most errors stem from missing Owner role at `/` scope:
```powershell
az role assignment list --assignee "<spn-object-id>" --scope "/"
```

### Role Assignment Scope Resolution

Scopes support both:
- Subscription aliases (e.g., `sub-visualstudio-enterprise`) → resolved via `data.azurerm_subscription`
- Full ARM resource IDs → used directly

### OIDC Federation Subjects

**GitHub**: `repo:frasermolyneux/{repo}:environment:{Environment}`
**Azure DevOps**: Dynamically set from service endpoint issuer/subject

## Key Implementation Files

- `workloads.load.tf`: Discovery via `fileset()` with examples exclusion
- `azure-workloads.tf`: Core SPN and GitHub resources
- `azure-workloads.if-*.tf`: Conditional resources by feature flag
- `azure-workloads.role-assignments.tf`: Scope resolution logic
- `azure-workloads.rbac.tf`: ABAC condition generation for role administrators

## Troubleshooting Patterns

### Workload Environment Key Format

All resources keyed by `"{workload-name}-{environment-name}"` (e.g., `geo-location-Development`):
```bash
terraform state show 'azuread_application.workload["geo-location-Development"]'
```

### RBAC Administrator Conditions

Generated ABAC conditions use GUID lookups from `data.azurerm_role_definition`. View generated conditions:
```bash
terraform state show 'azurerm_role_assignment.workload_rbac_administrator["platform-strategic-services-Production-sub-platform-strategic-0"]'
```

### Terraform State Storage Role Requirements

Service principals need THREE roles on state storage accounts:
- Storage Account Key Operator Service Role (Terraform requirement)
- Storage Blob Data Contributor (state read/write)
- Reader (resource metadata)
