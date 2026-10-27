# Architecture

## System Design

**Pattern**: JSON catalog definitions → `fileset()` discovery → Terraform conditionally generates repository governance and workload infrastructure.

**Core Flow**:
```
terraform/workloads/**/*.json (excluding examples/)
  ↓ fileset() in workloads.load.tf
  ↓ jsondecode() + flatten()
  ↓ definition mode
  ├→ Managed repository: GitHub repository settings + rulesets
  ├→ Policy-only repository: Rulesets on an existing GitHub repository
  └→ Environments, when present
      ├→ Azure AD: App registrations + SPNs + OIDC federation
      ├→ GitHub: Environments + variables
      └→ Azure RBAC: Role assignments (subscription aliases or ARM IDs)
```

### Catalog definition modes

- **Environment-backed workload**: includes `environments`; creates identity and
  integration resources in addition to the managed GitHub repository.
- **Managed repository only**: omits `environments`; creates the GitHub
  repository, modeled settings, labels, and rulesets, but no Azure identity,
  RBAC, state backend, or remote-state output.
- **Policy-only repository**: sets `github.manage_repository = false`; leaves
  repository lifecycle and general settings outside Terraform and reconciles
  only explicitly modeled policy resources.

The catalog includes application source repositories and operational data
repositories as well as environment-backed workloads. `platform-baremetal`
remains the central pull-based fleet-management workload for ns346663,
ns5019527, and ns512615, while `platform-baremetal-ns512615` is the separate
managed repository-only, data-only definition for delegated ns512615
operations. This stack owns their repository definitions and review governance,
not host configuration content, runtime access, or delegated operator
permissions.

## Key Implementation Patterns

### Workload Discovery (`workloads.load.tf`)

```hcl
locals {
  workload_json_files = [
    for file_path in fileset("${path.module}/workloads", "**/*.json") :
    file_path if !startswith(file_path, "examples/")
  ]
  workloads_from_files = [for f in local.workload_json_files : jsondecode(file(f))]
}
```

**Critical**: `examples/` exclusion happens at discovery, not in resource creation.

### Environment Keying

All resources use `"{workload-name}-{environment-name}"` as `for_each` key:
```hcl
resource "azuread_application" "workload" {
  for_each = { for e in local.workload_environments : e.key => e }
  display_name = format("spn-%s-%s", lower(e.value.workload_name), lower(e.value.environment_name))
}
```

### OIDC Federation Subjects

**GitHub**: `repo:frasermolyneux/{repo}:environment:{Environment}`

### Role Assignment Scope Resolution

```hcl
scope = startswith(each.value.scope, "/subscriptions/") 
  ? each.value.scope  # Full ARM resource ID
  : data.azurerm_subscription.subscriptions[each.value.scope].id  # Subscription alias
```

### RBAC Administrator ABAC Conditions

Generated conditions restrict role assignment/deletion to specific role definition GUIDs:
```hcl
condition = <<EOT
@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] 
  ForAnyOfAnyValues:GuidEquals {${join(", ", role_guids)}}
EOT
```

## Design Decisions

**JSON over HCL**: Enables non-Terraform users to add workloads. Trade-off: less type safety.

**OIDC over Secrets**: Eliminates secret rotation for GitHub Actions workload authentication.

### Dedicated on-premises status monitoring reader

`status-monitoring-reader.tf` owns a separate daemon application/service principal
and Monitoring Reader assignments on exact Application Insights resources. It has
no directory API permissions, redirects or client secrets. The public output
`status_monitoring_reader_identity` and status Production environment variables
expose identifiers only; the interactive status login application is unchanged.

The on-premises service cannot use an Azure-host managed identity. Its exception
is a certificate reader, not mounted deployment credentials. The existing
privileged platform-workloads GitHub OIDC identity performs lifecycle management;
no additional management privileges are granted to the reader or hosts.
`status-monitoring-certificate.yml` runs after successful production deployment,
weekly and on explicit dispatch. The script discovers exactly one dedicated app
and tagged status runtime vault, checks ownership/lifecycle metadata, and renews
180-day RSA certificates when 30 days remain or the registered public key is
missing. It never reads an existing private secret.

Registration uses append semantics, then verifies Entra client-credential
authentication before publishing the combined private PEM through the Key Vault
ARM secret endpoint. Registration/authentication failures do not replace the
existing secret. Previous public certificates remain valid until expiry plus
seven days; only expired keys with the managed prefix can be removed. Temporary
key files are runner-local and deleted on exit. Terraform state, logs and GitHub
artifacts must never receive the private key. Fleet policy mounts the versionless
secret into the status service only. Existing fleet reconciliation rebinds changed
secret versions; inode replacement alone is not visible through a file bind mount.
The consumer reloads its mounted certificate on each refresh.

**Conditional Resources via `if` in for_each**: Files named `azure-workloads.if-{feature}.tf` contain resources gated by flags (`connect_to_github`, `configure_for_terraform`, etc.).

### Personal-account repository governance

`frasermolyneux` is a personal GitHub account. Organization rulesets,
organization Copilot custom instructions, and organization-level Copilot
review defaults are therefore unavailable. Repository rulesets generated by
platform-workloads are the central governance substitute.

The canonical automatic-review contract is defined once in
`azure-workloads.rulesets.tf` and merged into each enrolled
`main-protection` ruleset:

- automatic Copilot review is enabled;
- draft pull requests are not reviewed;
- new pushes are not automatically re-reviewed, so the automatic review runs
  once when the pull request becomes ready for review.

Existing ruleset JSON remains authoritative for unrelated behavior including
status checks, approval requirements, thread resolution, linear history,
bypass actors, branch targets, and enforcement. When an enrolled
repository has no `main-protection` ruleset, Terraform creates a minimal
ruleset containing only the Copilot rule. Exceptions are explicit through
`github.repository_policy.copilot_code_review.enabled = false` and an
`exception_reason`.

New active managed software repositories are enrolled by default. Archived,
empty, external/upstream, generated/documentation-only, and other exceptional
repositories must opt out explicitly. Repository-native Copilot instructions
replace unavailable organization custom instructions. GitHub-hosted MCP and
review-MCP settings remain repository-local and must be inspected during each
repository migration. Direct ruleset edits in GitHub may be overwritten by
Terraform and should be avoided.

### Managed repository standards declaration

`azure-workloads.repository-standards.tf` derives standards enrollment from the
validated non-`xi-*` repository analysis catalog. Applicable profiles receive a
strict `REPOSITORY_STANDARDS` Actions variable; analysis exemptions receive no
variable. Terraform selects the fixed Checkov profile sequence from declared
languages and admits only bounded, rule-specific generated-content exceptions.
The same complete desired-state map is deterministically encoded in
`REPOSITORY_STANDARDS_CATALOG` on `platform-devex`, allowing its reconciler to
consume the catalog from its own `vars` context without target-repository
Variables permission. Per-target variables remain projected for repository-local
tooling and future use.

This is the desired-state declaration boundary. The separate platform-devex
reconciler is not active merely because the variable exists; its own rollout must
be merged and deployed before managed files are reconciled.

Copilot review effort is not represented in the GitHub Terraform provider
ruleset schema or a documented GitHub REST setting. Lite remains the GitHub
product default. Configure **Balanced** manually for `actions` and `portal-web`
at **Repository settings → Copilot → Code review → Review effort level**; do
not add unsupported API automation.

### Post-apply reconciliation

After the normal production pipeline applies the change, use read-only GitHub
REST requests to list each repository ruleset and fetch each ruleset detail:

```powershell
$repos = Get-ChildItem terraform\workloads -Recurse -Filter *.json |
  Where-Object FullName -NotMatch '\\examples\\' |
  ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json }

foreach ($repo in $repos) {
  $rulesets = gh api "repos/frasermolyneux/$($repo.name)/rulesets?includes_parents=false"
  # Fetch each returned ruleset with:
  # gh api "repos/frasermolyneux/$($repo.name)/rulesets/<ruleset-id>"
}
```

Confirm that every currently enrolled repository has exactly one
`copilot_code_review` rule with both options `false`, every catalog entry with
`enabled = false` has none, and no ruleset has duplicate Copilot rules. Derive
both sets from the current JSON catalog rather than a historical repository
count or hard-coded exception list. Compare all non-Copilot rule types,
parameters, conditions, bypass actors, targets, and enforcement against the
pre-apply plan/API inventory. No direct manual ruleset edit should be required.

**Owner at `/` Scope**: Required for service principal to assign RBAC across multiple subscriptions.

**Dual Role Assignments**: Service principal AND deploy script identity (managed identity) receive identical RBAC assignments when `add_deploy_script_identity: true`.

## File Organization

**Core Logic**:
- `workloads.load.tf`: Discovery via `fileset()`
- `azure-workloads.tf`: Base resources (SPN, GitHub repo)
- `azure-workloads.if-*.tf`: Feature-gated resources
- `azure-workloads.role-assignments.tf`: RBAC with scope resolution
- `azure-workloads.rbac.tf`: ABAC condition generation

**Workload Categories**: `terraform/workloads/{platform,portal,geo-location,misc,molyneux-me,xtremeidiots}/`
