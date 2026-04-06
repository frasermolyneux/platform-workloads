# Decommissioning a Workload

This guide explains how to safely decommission a workload managed by `platform-workloads`. The process removes all Azure infrastructure, identity, and CI/CD resources while **preserving the GitHub repository**.

> **⚠️ Important:** The order of operations matters. You **must** detach the GitHub repository from Terraform state **before** deleting the workload JSON. Doing it in the wrong order will cause Terraform to error due to `prevent_destroy`. See the [step-by-step process](#step-by-step-process) below.

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

- **The GitHub repository itself** — code, history, issues, pull requests, and wiki are all retained. The repository is detached from Terraform management but continues to exist on GitHub.

## Prerequisites

Before decommissioning, ensure:

1. **No active workloads depend on this one** — check whether any other workload JSON references this workload via `requires_terraform_state_access` or `workload:` scope prefixes in role assignments. Decommissioning will destroy the Terraform state storage that dependents rely on.
2. **The workload's own Terraform stack has been destroyed first** — if the workload has its own `terraform/` folder with deployed infrastructure, run `terraform destroy` on that stack before decommissioning from `platform-workloads`. Otherwise, the service principal and state storage needed to manage that infrastructure will be deleted.
3. **You have a clean `main` branch** — the decommission should be done via a pull request to allow plan review.

## Step-by-Step Process

### Step 1 — Detach the GitHub Repository from State

> **This must be done first.** The `github_repository.workload` resource has `lifecycle { prevent_destroy = true }`, which means Terraform will refuse to destroy it. You must remove it from state before deleting the workload JSON, otherwise the Terraform plan will fail.

Run the **Decommission State Rm** workflow:

1. Go to **Actions → Decommission State Rm** in this repository.
2. Click **Run workflow**.
3. Enter the workload name — this is the `"name"` value from the workload JSON file (e.g. `portal-event-ingest`).
4. Wait for the workflow to complete successfully.
5. Verify the post-removal plan output shows no unexpected changes.

The workflow runs `terraform state rm 'github_repository.workload["<workload-name>"]'` against the production state, detaching the repository without deleting it.

> **Why not use a `removed` block?** Terraform's `removed` block does not support `for_each` instance keys (e.g. `github_repository.workload["name"]`). It only works for whole resources. The `terraform state rm` approach via this workflow is the correct alternative.

### Step 2 — Delete the Workload JSON

Remove the workload definition file from `terraform/workloads/{category}/`:

```bash
git rm terraform/workloads/{category}/{workload-name}.json
```

### Step 3 — Create a Pull Request

Commit the change and open a pull request:

```bash
git checkout -b decommission/{workload-name}
git add -A
git commit -m "chore: decommission {workload-name}"
git push origin decommission/{workload-name}
```

### Step 4 — Review the Terraform Plan

The PR verification workflow will run a Terraform plan. Review it carefully and confirm:

- ✅ The GitHub repository is **not** in the destroy list — it was already detached from state in step 1
- ✅ All expected Azure/identity/CI-CD resources are marked for destruction
- ✅ No unexpected resources are affected

> **If the plan shows the repository being destroyed**, step 1 was not completed. Go back and run the **Decommission State Rm** workflow first, then re-trigger the PR plan.

### Step 5 — Merge and Apply

Once the plan looks correct, merge the PR. The `deploy-prd` workflow will apply the changes automatically.

### Step 6 (Optional) — Transfer Repository to Archive

After the apply succeeds, you can transfer the repository to the `frasermolyneux-archive` organisation:

```bash
gh repo transfer frasermolyneux/{workload-name} frasermolyneux-archive --yes
```

This requires the GitHub CLI (`gh`) and a token with admin access to both organisations.

## Quick Reference

| Step | Action | How |
|------|--------|-----|
| 1 | Detach repo from state | **Actions → Decommission State Rm** → enter workload name |
| 2 | Delete workload JSON | `git rm terraform/workloads/{category}/{name}.json` |
| 3 | Open PR | Branch, commit, push |
| 4 | Review plan | Check PR plan — repo should NOT appear in destroy list |
| 5 | Merge | Merge PR → `deploy-prd` applies automatically |
| 6 | Archive (optional) | `gh repo transfer` to `frasermolyneux-archive` |

## Troubleshooting

### Terraform errors with "Instance cannot be destroyed"

The workload JSON was deleted but the GitHub repository was not detached from state first. Run the **Decommission State Rm** workflow (step 1) to remove the repository from state, then re-run the plan.

### Terraform errors with "Resource instance keys not allowed" in `removed.tf`

A `removed` block was used with a `for_each` instance key (e.g. `github_repository.workload["name"]`). This is not supported by Terraform. Delete `removed.tf` and use the **Decommission State Rm** workflow to detach the instance from state instead.

### Need to re-onboard a decommissioned workload

If you need to bring a workload back under management:

1. Re-create the workload JSON file.
2. Import the existing repository into state:
   ```bash
   terraform import 'github_repository.workload["workload-name"]' workload-name
   ```
3. Run `terraform plan` to reconcile any drift.

### Dependent workloads broke after decommission

If another workload referenced the decommissioned one via `requires_terraform_state_access`, it will lose access to the destroyed state storage. Update the dependent workload's JSON to remove the reference, and reconfigure its Terraform backend if needed.
