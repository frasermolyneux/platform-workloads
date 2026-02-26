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
| `CLOUDFLARE_API_KEY`         | Cloudflare Global API Key                         |
| `CLOUDFLARE_EMAIL`           | Cloudflare account email                          |

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

## Cloudflare Authentication

Cloudflare provider uses the Global API Key (not a scoped API token) because the `cloudflare_api_token_permission_groups` data source requires user-level API access that scoped tokens cannot provide.

Add these as GitHub environment secrets on the `Production` environment of `platform-workloads`:

| Secret             | Value                                                        |
| ------------------ | ------------------------------------------------------------ |
| `CLOUDFLARE_API_KEY` | Global API Key from [Cloudflare dashboard](https://dash.cloudflare.com/profile/api-tokens) |
| `CLOUDFLARE_EMAIL`   | The email address associated with the Cloudflare account     |

The Global API Key is used by Terraform to create scoped, per-workload API tokens with minimal permissions (e.g., DNS Write on a specific zone).
