# Platform Workloads

[![DevOps Secure Scanning](https://github.com/frasermolyneux/platform-workloads/actions/workflows/devops-secure-scanning.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/devops-secure-scanning.yml)
[![Feature Development](https://github.com/frasermolyneux/platform-workloads/actions/workflows/feature-development.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/feature-development.yml)
[![Release to Production](https://github.com/frasermolyneux/platform-workloads/actions/workflows/release-to-production.yml/badge.svg)](https://github.com/frasermolyneux/platform-workloads/actions/workflows/release-to-production.yml)

## 📚 Documentation

- **[Architecture](docs/architecture.md)** - System design, component overview, and key patterns
- **[Workload Configuration Guide](docs/workload-configuration.md)** - Complete JSON schema reference and examples
- **[Developer Guide](docs/developer-guide.md)** - Setup instructions, workflow, and troubleshooting
- **[Prerequisites](docs/prerequisites.md)** - Required setup for service principals and permissions

## Overview

**Declarative infrastructure automation** using JSON-driven Terraform to manage Azure AD service principals, GitHub/Azure DevOps configurations, and RBAC assignments for multiple workloads.

**What It Does**:
- Creates service principals with OIDC federation (password-less auth)
- Provisions GitHub repos with environments and variables
- Configures Azure DevOps service connections and variable groups
- Assigns Azure RBAC roles across subscriptions/resources
- Provisions Terraform state storage per workload

**How**: JSON files in `terraform/workloads/{category}/` \u2192 `fileset()` discovery \u2192 Terraform generates infrastructure

## Quick Start

Create `terraform/workloads/{category}/workload-name.json`:

```json
{
  "name": "workload-name",
  "github": {
    "description": "Description of the workload",
    "topics": ["azure"],
    "visibility": "public"
  },
  "environments": [
    {
      "name": "Development",
      "subscription": "sub-visualstudio-enterprise",
      "connect_to_github": true,
      "devops_project": "ProjectName",
      "configure_for_terraform": true,
      "role_assignments": [
        {
          "scope": "sub-visualstudio-enterprise",
          "role_definitions": ["Contributor"]
        }
      ]
    }
  ]
}
```

Commit and push \u2014 Terraform auto-discovers and applies. See [Workload Configuration](docs/workload-configuration.md) for full schema.

## Developer-backend-config="backends/prd.backend.hcl"

# Plan changes
terraform plan -var-file="tfvars/prd.tfvars"
```

### Common Commands

```bash
# Format Terraform code
terraform fmt -recursive

# Validate configuration
terraform validate

# Preview changes
terraform plan -var-file="tfvars/prd.tfvars"

# Apply changes
terraform apply -var-file="tfvars/prd.tfvars"
```

📖 See the [Developer Guide](docs/developer-guide.md) for detailed setup, workflow, and troubleshooting.

## Key Conventions

- **Service Principal Naming**: `spn-{workload-name}-{environment-name}` (lowercase)
- **Resource Naming**: `{type}-{workload}-{env}-{location}-{instance}`
- **Environment Mapping**: Development→dev, Testing→tst, Production→prd
- **Tenant ID**: `e56a6947-bb9a-4a6e-846a-1f118d1c3a14` (hard-coded)

## Contributing

1. Create workload JSON file in appropriate category
2. Run `terraform fmt -recursive` before committing
3. Test with `terraform plan` to verify changes
4. Commit with clear, descriptive message
5. Push and monitor GitHub Actions workflow

## Support

For issues, questions, or contributions, please refer to:
- [Architecture documentation](docs/architecture.md) for design patterns
- [Developer Guide](docs/developer-guide.md) for troubleshooting
- Existing workload files for examplesPatterns

- **Service Principal**: `spn-{workload}-{environment}` (lowercase)
- **OIDC GitHub Subject**: `repo:frasermolyneux/{repo}:environment:{Environment}`
- **Resource Key**: `{workload-name}-{environment-name}` in all `for_each` loops
- **Scope Resolution**: Subscription aliases OR full ARM resource IDs
- **Examples Exclusion**: `workloads/examples/` filtered in `workloads.load.tf`
- **Environment Mapping**: Development\u2192dev, Testing\u2192tst, Production\u2192prd
- **Tenant ID**: `e56a6947-bb9a-4a6e-846a-1f118d1c3a14` (hard-coded)