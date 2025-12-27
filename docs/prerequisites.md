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

## Owner Role Assignment

```powershell
az role assignment create --scope '/' --role 'Owner' \
  --assignee-object-id $(az ad sp list --display-name "spn-platform-workloads-production" --query '[].id' -o tsv) \
  --assignee-principal-type ServicePrincipal
```

## Key Vault Tokens

NuGet and SonarCloud tokens stored in Key Vault are injected into workload GitHub secrets. First-time runs fail if secrets don't exist.
