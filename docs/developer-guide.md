# Developer Guide

Audience: senior engineers running and evolving platform-workloads Terraform.

## Environment Setup
- Select the exact Terraform CLI version in [`terraform/.terraform-version`](../terraform/.terraform-version); the compatibility constraint is in [`providers.tf`](../terraform/providers.tf).
- Azure CLI logged in (az login) and subscription set to match the tfvars backend/alias you plan to use.
- Environment variable: GITHUB_TOKEN with rights for the GitHub provider.
- The platform service principal must be Owner at / scope.

## Provider Dependency Policy

Commit each root's `.terraform-version` and `.terraform.lock.hcl`. Select the exact root CLI pin before invoking Terraform; normal initialization uses `-lockfile=readonly`. Regenerate provider selections only in a reviewed dependency-update PR; never commit state, plans, or `.terraform/`.

## Running Terraform Locally
1. From repository root: `cd terraform`
2. Initialize against the production backend:

```bash
terraform init -lockfile=readonly -backend-config="backends/prd.backend.hcl"
```

3. Plan:

```bash
terraform plan -var-file="tfvars/prd.tfvars"
```

4. Apply after review:

```bash
terraform apply -var-file="tfvars/prd.tfvars"
```

5. Keep formatting clean before committing: `terraform fmt -recursive`.

### Analysis catalog validation

After backend-disabled initialization, validate the scoped analysis contract without
Azure/GitHub provider reads:

```powershell
terraform -chdir=terraform test '-var-file=tfvars\prd.tfvars' '-filter=tests\repository-analysis.tftest.hcl'
```

This metadata-only test targets the built-in contract resource and checks catalog
dispositions, declared variables, private publication boundaries and exclusions.
It does not replace the full production state-backed plan or justify
targeted production applies. Analysis variables are configuration, not proof of
scanner execution or estate caller adoption.

### Repository standards validation

Validate the managed Checkov, analyzer, Sonar and ESLint declaration contract without provider reads:

```powershell
terraform -chdir=terraform test '-var-file=tfvars\prd.tfvars' '-filter=tests\repository-standards.tftest.hcl'
```

The test checks applicable public and private counts, deterministic profile
selection, the Trip Side Kick generated OpenAPI exception, Portal Server Agent fixture
exception, Geo Location vendor exclusions, exclusion of analysis
exemptions and `xi-*` repositories, and exact aggregate-catalog key/document parity.
It also verifies the `platform-devex` target and conservative encoded-size bound.
The aggregate is consumed from platform-devex's own `vars` context; per-target
variables remain projected for repository-local tooling and future use. The test
validates desired-state projection only; platform-devex reconciliation is a
separate rollout.

### Targeted Operations
- Validate a new workload file: `Get-Content terraform/workloads/platform/new-workload.json | ConvertFrom-Json`
- Plan a single resource to reduce noise: `terraform plan -var-file="tfvars/prd.tfvars" -target='github_repository.workload["portal-core"]'`
- Inspect generated resources: `terraform state show 'azuread_application.workload["geo-location-Development"]'`

## Working with Workloads
- Add JSON under terraform/workloads/{category}/; examples in terraform/workloads/platform/ and portal/ show production patterns.
- Choose the definition mode deliberately: environments create workload identity and integration resources; omitting environments creates a managed repository only; `github.manage_repository=false` manages policy on an existing repository only.
- Keep repository content, collaborator access, runtime configuration, and operator boundaries in the owning repository. `platform-workloads` manages only the resources modeled in the catalog.
- Files under terraform/workloads/examples/ are ignored by design.
- Reader is auto-added at the environment subscription; see [Role Assignments](role-assignments.md) for how existing entries are matched.
- Scope inputs accept aliases from var.subscriptions, raw ARM IDs, workload: and workload-rg: helpers (see docs/workload-configuration.md).

## CI Workflows
- `Build and Test` runs formatting, backend-disabled initialization, validation, selected Terraform contract tests and the GitHub App bootstrap tests for matching branch and path filters.
- `Feature Development` runs production-backed plans for matching feature branches.
- `PR Verify` plans non-draft pull requests.
- PR comments report status and change counts, not resource-level plan details. Review the Terraform Plan step's workflow logs for the complete plan.
- Plan and deploy jobs store saved plans in the production backend account's private `tfplan` container using OIDC. Storage failure fails the job and prevents deployment.
- Running Terraform PR plans are not cancelled by a new push; production jobs retain their shared concurrency group so state locks can be released normally.
- `Deploy Prd` applies qualifying changes pushed to `main`, and also runs on its schedule or by dispatch.
- `Decommission State Rm` is the explicit repository-detachment operation used before deleting a managed repository definition.
Inspect `.github/workflows` for current triggers and required Production environment credentials before depending on them.

## Troubleshooting Quick Checks
- An orphaned Terraform state lock requires explicit operator approval after confirming its exact ID and that the owning job and other state writers have stopped. Do not disable locking or force-unlock an active operation.
- Permission failures: confirm the platform service principal is Owner at / (`az role assignment list --assignee <spn-object-id> --scope /`).
- Scope resolution errors: ensure the alias exists in tfvars/prd.tfvars or supply a full ARM ID.
- OIDC federation: GitHub uses repo:frasermolyneux/{repo}:environment:{Environment}.
- Terraform state storage access: workload principals need Storage Account Key Operator Service Role, Storage Blob Data Contributor, and Reader on the storage account created per workload when configure_for_terraform is true.
- Each Terraform-enabled workload environment has private `tfstate` and `tfplan` containers in its storage account. Account-scoped blob grants also apply to both containers.
- Workload storage accounts enable blob versioning and account-level blob soft delete, covering both containers and other blobs in the account. This stack does not manage the separately bootstrapped platform-workloads backend's blob settings.
- A lifecycle rule scoped to `tfplan/` deletes old block blobs, snapshots and previous versions. Azure evaluates lifecycle rules asynchronously; see [`azure-workloads.if-terraform.tf`](../terraform/azure-workloads.if-terraform.tf) for the current retention settings.
- No lifecycle deletion applies to `tfstate` or its previous versions. Versioning can therefore increase storage usage over time; review state-version growth separately.
