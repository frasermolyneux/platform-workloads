# Prerequisites

## Service Principal Configuration

1. **App Registration**: `spn-platform-workloads-production`
   - Entra ID: Global Administrator role
   - RBAC: Owner at `/` scope (required for cross-subscription role assignments)

2. **Federated Credential**: GitHub Actions deploying Azure resources
   - Subject: `repo:frasermolyneux/platform-workloads:environment:Production`

3. **GitHub Environment Variables and Secrets** (`Production`):

| Variable                     | Purpose                                           |
| ---------------------------- | ------------------------------------------------- |
| `AZURE_CLIENT_ID`            | App registration client ID                        |
| `AZURE_SUBSCRIPTION_ID`      | Management subscription ID                        |
| `AZURE_TENANT_ID`            | Entra tenant ID                                   |

| Secret                       | Purpose                                           |
| ---------------------------- | ------------------------------------------------- |
| `TERRAFORM_GITHUB_TOKEN`     | GitHub provider authentication                    |
| `CLOUDFLARE_API_KEY`         | Cloudflare Global API Key                         |
| `CLOUDFLARE_EMAIL`           | Cloudflare account email                          |

4. **Saved plan storage**: The separately bootstrapped production backend
   storage account must have a private `tfplan` container. The Production OIDC
   identity needs Storage Blob Data Contributor access to that container; the
   existing account-scoped grant also satisfies this requirement.

## Owner Role Assignment

```powershell
az role assignment create --scope '/' --role 'Owner' `
  --assignee-object-id $(az ad sp list --display-name "spn-platform-workloads-production" --query '[].id' -o tsv) `
  --assignee-principal-type ServicePrincipal
```

## Key Vault Tokens

The following tokens must be stored in the platform-workloads Key Vault. First-time runs fail if referenced secrets don't exist.

| Secret Name                            | Purpose                                                                                                         |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `sonarcloud-token`                     | SonarCloud token injected into workload GitHub secrets (for workloads with `add_sonarcloud_secrets`)             |

Terraform also creates a `github-app-pem` placeholder whose value is managed
outside Terraform. Replace it with the shared App's private key before enabling
the shared GitHub App integration. See [`key_vault.tf`](../terraform/key_vault.tf).

## Cloudflare Authentication

Cloudflare provider uses the Global API Key (not a scoped API token) because the `cloudflare_api_token_permission_groups` data source requires user-level API access that scoped tokens cannot provide.

Add these as GitHub environment secrets on the `Production` environment of `platform-workloads`:

| Secret             | Value                                                        |
| ------------------ | ------------------------------------------------------------ |
| `CLOUDFLARE_API_KEY` | Global API Key from [Cloudflare dashboard](https://dash.cloudflare.com/profile/api-tokens) |
| `CLOUDFLARE_EMAIL`   | The email address associated with the Cloudflare account     |

The Global API Key is used by Terraform to create scoped, per-workload API tokens with minimal permissions (e.g., DNS Write on a specific zone).
