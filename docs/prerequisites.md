# Prerequisites

## Service Principal Configuration

1. **App Registration**: `spn-platform-workloads-production`
   - Entra ID: Global Administrator role
   - RBAC: Owner at `/` scope (required for cross-subscription role assignments)

2. **Federated Credential**: GitHub Actions deploying Azure resources
   - Subject: `repo:frasermolyneux/platform-workloads:environment:Production`

3. **GitHub Environment Secrets** (`Production`):

| Secret                       | Purpose                                           |
| ---------------------------- | ------------------------------------------------- |
| `AZDO_PERSONAL_ACCESS_TOKEN` | Azure DevOps provider authentication              |
| `AZURE_CLIENT_ID`            | App registration client ID                        |
| `AZURE_SUBSCRIPTION_ID`      | Management subscription ID                        |
| `AZURE_TENANT_ID`            | Tenant ID: `e56a6947-bb9a-4a6e-846a-1f118d1c3a14` |
| `TERRAFORM_GITHUB_TOKEN`     | GitHub provider authentication                    |
| `TERRAFORM_CLOUDFLARE_BOOTSTRAP_TOKEN` | Cloudflare provider authentication (API Tokens Edit) |

## Owner Role Assignment

```powershell
az role assignment create --scope '/' --role 'Owner' \
  --assignee-object-id $(az ad sp list --display-name "spn-platform-workloads-production" --query '[].id' -o tsv) \
  --assignee-principal-type ServicePrincipal
```

## Key Vault Tokens

The following tokens must be stored in the platform-workloads Key Vault. First-time runs fail if referenced secrets don't exist.

| Secret Name                            | Purpose                                                                                                         |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `nuget-token`                          | NuGet API key injected into workload GitHub environment secrets (for workloads with `add_nuget_environment`)     |
| `sonarcloud-token`                     | SonarCloud token injected into workload GitHub secrets (for workloads with `add_sonarcloud_secrets`)             |

## Cloudflare Bootstrap Token

The Cloudflare bootstrap token is passed as a GitHub environment secret (`TERRAFORM_CLOUDFLARE_BOOTSTRAP_TOKEN`) on the `Production` environment of `platform-workloads`, following the same pattern as `AZDO_PERSONAL_ACCESS_TOKEN` and `TERRAFORM_GITHUB_TOKEN`.

The Cloudflare provider reads it via the `CLOUDFLARE_API_TOKEN` environment variable (mapped in workflows).

### Creating the Cloudflare Bootstrap Token

1. Log in to the [Cloudflare dashboard](https://dash.cloudflare.com/profile/api-tokens)
2. Create a new API token with **only** the `User > API Tokens > Edit` permission
3. Add it as a GitHub environment secret named `TERRAFORM_CLOUDFLARE_BOOTSTRAP_TOKEN` on the `Production` environment of the `platform-workloads` repository

This bootstrap token allows Terraform to create scoped, per-workload API tokens with minimal permissions (e.g., DNS Write on a specific zone).
