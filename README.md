# Platform Workloads

[![DevOps Secure Scanning](https://github.com/frasermolyneux/platform-workloads/actions/workflows/devops-secure-scanning.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/devops-secure-scanning.yml)
[![Feature Development](https://github.com/frasermolyneux/platform-workloads/actions/workflows/feature-development.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/feature-development.yml)
[![Release to Production](https://github.com/frasermolyneux/platform-workloads/actions/workflows/release-to-production.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/release-to-production.yml)

## What This Repository Delivers
- JSON-driven Terraform that provisions Azure AD applications/service principals with OIDC, GitHub repositories/environments, Azure DevOps service connections/variable groups, and workload-scoped RBAC.
- Per-workload Terraform state storage (resource group + storage account + container) when configure_for_terraform is enabled.
- Delegated RBAC administration via conditional Role Based Access Control Administrator assignments limited to explicitly allowed roles.

## How It Works
1. Workload JSON files in terraform/workloads/** (excluding examples/) are discovered in terraform/workloads.load.tf and decoded into locals.
2. Environments flatten into a keyed map ({workload}-{environment}) consumed by resources in terraform/azure-workloads.tf.
3. Feature-gated stacks in the azure-workloads.if-*.tf files create GitHub environments/OIDC, Azure DevOps service endpoints/environments/variable groups, and optional Terraform state resources.
4. Scope resolution and RBAC expansion live in terraform/azure-workloads.role-assignments.tf; ABAC-conditioned RBAC admin assignments are generated in terraform/azure-workloads.rbac.tf.

## Quick Start (Senior Path)
1. Authenticate locally: az login and set environment variables AZDO_PERSONAL_ACCESS_TOKEN, GITHUB_TOKEN, and optionally AZDO_GITHUB_SERVICE_CONNECTION_PAT for github_service_connection_pat.
2. Run Terraform from terraform/:

```bash
cd terraform
terraform init -backend-config="backends/prd.backend.hcl"
terraform fmt -recursive
terraform plan -var-file="tfvars/prd.tfvars" -var "github_service_connection_pat=$env:AZDO_GITHUB_SERVICE_CONNECTION_PAT"

# Target a specific workload resource if needed
terraform plan -var-file="tfvars/prd.tfvars" -target='github_repository.workload["portal-core"]'

# Apply once satisfied
terraform apply -var-file="tfvars/prd.tfvars"
```

3. Add a workload: place a JSON file under terraform/workloads/{category}/, then re-run terraform plan and terraform apply.

## Repository Map
- terraform/workloads.load.tf - JSON discovery with examples/ exclusion.
- terraform/azure-workloads.tf - Core SPN/app registration and GitHub repository creation.
- terraform/azure-workloads.if-github.tf - GitHub environments, OIDC federation, and environment variables.
- terraform/azure-workloads.if-devops.tf - Azure DevOps service connections, environments, checks, and variable groups.
- terraform/azure-workloads.if-terraform.tf - Terraform state resource groups, storage accounts, and access roles.
- terraform/azure-workloads.role-assignments.tf - Role assignment expansion and scope resolution (aliases, ARM IDs, workload references).
- terraform/azure-workloads.rbac.tf - Conditional RBAC admin delegation with allowed-role enforcement.
- Workload catalog: terraform/workloads/ with production-ready examples in platform/, portal/, geo-location/, etc.

## Conventions and Guardrails
- Service principal naming: spn-{workload}-{environment} (lowercase). Resource naming: {type}-{workload}-{env}-{location}-{instance}.
- Environment mapping: Development->dev, Testing->tst, Production->prd (var.environment_map).
- Reader auto-injection: if no subscription-level assignment exists for an environment, a Reader role is added at that subscription; if one exists, Reader is merged into its roles.
- Scope inputs: subscription aliases from var.subscriptions, raw ARM IDs, workload: and workload-rg: helpers. Examples under workloads/examples/ are ignored.
- OIDC subjects: GitHub repo:frasermolyneux/{repo}:environment:{Environment}; Azure DevOps issuer/subject sourced from the service endpoint.
- Tenant ID is hard-coded to e56a6947-bb9a-4a6e-846a-1f118d1c3a14; default location and instance come from var.location and var.instance.

## Documentation
- Architecture - end-to-end design and key Terraform patterns (docs/architecture.md).
- Workload Configuration - full JSON schema, scope resolution options, and examples (docs/workload-configuration.md).
- Developer Guide - local workflow, targeting, and troubleshooting (docs/developer-guide.md).
- Prerequisites - required identities, roles, and GitHub environment secrets (docs/prerequisites.md).