# Developer Guide

Audience: senior engineers running and evolving platform-workloads Terraform.

## Environment Setup
- Terraform >= 1.14.0
- Azure CLI logged in (az login) and subscription set to match the tfvars backend/alias you plan to use.
- Environment variables: AZDO_PERSONAL_ACCESS_TOKEN, GITHUB_TOKEN, and optionally AZDO_GITHUB_SERVICE_CONNECTION_PAT (used for github_service_connection_pat).
- PATs must have rights for the Azure DevOps and GitHub providers; the platform service principal must be Owner at / scope.

## Running Terraform Locally
1. From repository root: `cd terraform`
2. Initialize against the production backend:

```bash
terraform init -backend-config="backends/prd.backend.hcl"
```

3. Plan (include the GitHub service connection PAT if required):

```bash
terraform plan -var-file="tfvars/prd.tfvars" -var "github_service_connection_pat=$env:AZDO_GITHUB_SERVICE_CONNECTION_PAT"
```

4. Apply after review:

```bash
terraform apply -var-file="tfvars/prd.tfvars"
```

5. Keep formatting clean before committing: `terraform fmt -recursive`.

### Targeted Operations
- Validate a new workload file: `Get-Content terraform/workloads/platform/new-workload.json | ConvertFrom-Json`
- Plan a single resource to reduce noise: `terraform plan -var-file="tfvars/prd.tfvars" -target='github_repository.workload["portal-core"]'`
- Inspect generated resources: `terraform state show 'azuread_application.workload["geo-location-Development"]'`

## Working with Workloads
- Add JSON under terraform/workloads/{category}/; examples in terraform/workloads/platform/ and portal/ show production patterns.
- Files under terraform/workloads/examples/ are ignored by design.
- Reader is auto-added at the environment subscription when no assignment targets that scope; if an assignment exists, Reader is merged into its roles.
- Scope inputs accept aliases from var.subscriptions, raw ARM IDs, workload: and workload-rg: helpers (see docs/workload-configuration.md).

## CI Workflows
- DevOps Secure Scanning runs repository checks.
- Feature Development drives PR validation.
- Release to Production runs promotion for mainline changes.
Inspect .github/workflows for triggers and any required environment secrets before depending on them.

## Troubleshooting Quick Checks
- Permission failures: confirm the platform service principal is Owner at / (`az role assignment list --assignee <spn-object-id> --scope /`).
- Scope resolution errors: ensure the alias exists in tfvars/prd.tfvars or supply a full ARM ID.
- OIDC federation: GitHub uses repo:frasermolyneux/{repo}:environment:{Environment}; Azure DevOps issuer/subject come from the service endpoint.
- Terraform state storage access: workload principals need Storage Account Key Operator Service Role, Storage Blob Data Contributor, and Reader on the storage account created per workload when configure_for_terraform is true.