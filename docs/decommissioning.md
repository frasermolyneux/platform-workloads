# Decommissioning a Workload

This guide explains how to safely decommission a workload managed by `platform-workloads`. The process removes all Azure infrastructure, identity, and CI/CD resources while **preserving the GitHub repository**.

## What Gets Destroyed

When a workload is decommissioned, Terraform destroys:

- Azure AD application and service principal (per environment)
- OIDC federated identity credentials (GitHub and Azure DevOps)
- RBAC role assignments (all scopes)
- Terraform state storage (resource group, storage account, container)
- GitHub repository environments, secrets, and environment variables
- GitHub issue labels and repository rulesets
- Azure DevOps service connections, environments, and variable groups
- Cloudflare API tokens (if configured)
- Azure resource groups created by the workload definition
- Directory role assignments and administrative unit memberships
- Graph API permission grants

## What Is Preserved

- **The GitHub repository itself** — code, history, issues, pull requests, and wiki are all retained

## Prerequisites

Before decommissioning, ensure:

1. **No active workloads depend on this one** — check whether any other workload JSON references this workload via `requires_terraform_state_access` or `workload:` scope prefixes in role assignments. Decommissioning will destroy the Terraform state storage that dependents rely on.
2. **The workload's own Terraform stack has been destroyed first** — if the workload has its own `terraform/` folder with deployed infrastructure, run `terraform destroy` on that stack before decommissioning from `platform-workloads`. Otherwise, the service principal and state storage needed to manage that infrastructure will be deleted.
3. **You have a clean `main` branch** — the decommission should be done via a pull request to allow plan review.

## Step-by-Step Process

### 1. Delete the Workload JSON

Remove the workload definition file from `terraform/workloads/{category}/`:

```bash
git rm terraform/workloads/{category}/{workload-name}.json
```

### 2. Add a `removed` Block

Add a `removed` block to `terraform/removed.tf` (create the file if it does not exist). This tells Terraform to remove the GitHub repository from state **without destroying it**:

```hcl
removed {
  from = github_repository.workload["workload-name"]

  lifecycle {
    destroy = false
  }
}
```

Replace `workload-name` with the exact value of the `"name"` field from the deleted JSON file.

> **Why is this needed?** The `github_repository.workload` resource has `lifecycle { prevent_destroy = true }` as a safety net. If you delete the JSON without the `removed` block, Terraform will error and refuse to proceed — protecting the repository from accidental deletion. The `removed` block is the explicit opt-in to say "I want to detach this repo from Terraform management."

### 3. Create a Pull Request

Commit both changes and open a pull request:

```bash
git checkout -b decommission/{workload-name}
git add -A
git commit -m "chore: decommission {workload-name}"
git push origin decommission/{workload-name}
```

### 4. Review the Terraform Plan

The PR verification workflow will run a Terraform plan. Review it carefully and confirm:

- ✅ The GitHub repository is **not** in the destroy list (it should show as "removed from state" or simply not appear)
- ✅ All expected Azure/identity/CI-CD resources are marked for destruction
- ✅ No unexpected resources are affected

### 5. Merge and Apply

Once the plan looks correct, merge the PR. The `deploy-prd` workflow will apply the changes automatically.

### 6. (Optional) Transfer Repository to Archive

After the apply succeeds, you can transfer the repository to the `frasermolyneux-archive` organisation to remove it from the main org's view:

```bash
gh repo transfer frasermolyneux/{workload-name} frasermolyneux-archive --yes
```

This requires the GitHub CLI (`gh`) and a token with admin access to both organisations.

### 7. Clean Up the `removed` Block

In a follow-up PR, remove the `removed` block from `terraform/removed.tf`. Once the repository is no longer in Terraform state, the block is inert and can be safely deleted. If the file is empty after cleanup, delete it entirely.

## Troubleshooting

### Terraform errors with "Instance cannot be destroyed"

This means the workload JSON was deleted but no `removed` block was added. The `prevent_destroy` lifecycle rule is protecting the repository. Add the `removed` block as described in step 2.

### Need to re-onboard a decommissioned workload

If you need to bring a workload back under management:

1. Re-create the workload JSON file
2. Remove the `removed` block (if still present)
3. Import the existing repository into state:
   ```bash
   terraform import 'github_repository.workload["workload-name"]' workload-name
   ```
4. Run `terraform plan` to reconcile any drift

### Dependent workloads broke after decommission

If another workload referenced the decommissioned one via `requires_terraform_state_access`, it will lose access to the destroyed state storage. Update the dependent workload's JSON to remove the reference, and reconfigure its Terraform backend if needed.
