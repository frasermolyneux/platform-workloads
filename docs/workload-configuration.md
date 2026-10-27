# Workload Configuration Reference

## Schema Overview

JSON files in `terraform/workloads/{category}/` form a shared workload and
repository catalog. Resources depend on the definition shape:

| Definition mode | Required shape | Managed resources |
| --- | --- | --- |
| Environment-backed workload | One or more `environments` | Managed GitHub repository plus per-environment identity, integrations, RBAC, and optional state infrastructure |
| Managed repository only | `github.manage_repository` omitted or `true`; no `environments` | GitHub repository settings, labels, rulesets and applicable analysis variables; no Azure workload resources |
| Policy-only repository | `github.manage_repository: false` | Rulesets, applicable analysis variables and explicitly opted-in existing Sonar token projection; no repository lifecycle management |

Repository-only governance entries use the same catalog under
`terraform/workloads/repository-governance/`. Setting
`github.manage_repository` to `false` leaves repository lifecycle and settings
outside Terraform while allowing repository rulesets to be reconciled through
the shared policy model. An explicit `add_sonarcloud_secrets` opt-in can also project
the existing Key Vault-backed Sonar token to the named repository without importing
its lifecycle or general settings. This keeps one repository catalog without importing
non-workload repositories into `github_repository.workload`. Applicable analysis metadata
uses the same lifecycle-safe repository-name resolution.

Omitting `environments` is intentional for repository-only definitions and
creates no Azure application, service principal, RBAC, state backend, or
remote-state output. Repository content, collaborators, runtime access, host
bindings, and application deployment configuration remain owned by the target
repository or its operational control plane.

Repository-only entries may declare a singular top-level `environment` string
as runtime inventory metadata (for example `Production` or `Staging`). Radar uses
this to validate authenticated deployment observations. It is not the plural
`environments` provisioning array: it creates no GitHub environment, Azure identity,
RBAC, state backend or remote-state environment output. The native host policy
still independently enrolls the service and its environment; catalog metadata
alone does not establish a deployed runtime.

## JSON Structure

```json
{
  "name": "workload-name",
  "github": {
    "description": "Description of the workload",
    "topics": ["azure", "terraform", "devops"],
    "visibility": "public",
    "has_downloads": false,
    "has_issues": true,
    "has_projects": false,
    "has_wiki": false,
    "auto_init": false,
    "is_template": false,
    "add_sonarcloud_secrets": false,
    "add_nuget_environment": false,
    "github_app": {
      "enabled": false,
      "app_id": null,
      "installation_id": null
    },
    "manage_repository": true,
    "repository_analysis": {
      "profile": {
        "version": "repository-analysis-v1",
        "languages": ["actions", "terraform"],
        "sonar": false
      },
      "sonar": null,
      "cadence": {
        "dailyFreshness": true,
        "fullRescanMaximumHours": 168,
        "defaultBranchCancellation": false,
        "dispatch": {
          "expectedRevision": true,
          "force": true,
          "defaultBranchOnly": true
        }
      }
    },
    "repository_standards": {
      "checkov": {
        "exceptions": [
          {
            "rule": "CKV_OPENAPI_21",
            "reason": "Generated OpenAPI content cannot express this reviewed constraint; runtime validation enforces it."
          }
        ]
      }
    },
    "repository_policy": {
      "copilot_code_review": {
        "enabled": true,
        "exception_reason": null
      }
    }
  },
  "environments": [...]
}
```

The analysis profile above illustrates an Actions/Terraform repository. Classify
the actual maintained source when adding an entry; use a reasoned exemption for
an empty, archived, documentation-only or upstream-fork repository instead.

### Environment Configuration

```json
{
  "name": "Development",
  "subscription": "sub-visualstudio-enterprise",
  "connect_to_github": true,
  "configure_for_terraform": true,
  "add_deploy_script_identity": true,
  "role_assignments": {
    "assigned_roles": [
      { "roles": ["Contributor"] },
      {
        "scope": "/subscriptions/.../resourceGroups/...",
        "roles": ["DNS Zone Contributor"]
      }
    ],
    "rbac_admin_roles": [
      { "allowed_roles": ["Key Vault Secrets User"] }
    ]
  },
  "directory_roles": [...],
  "graph_api_permissions": ["AppRoleAssignment.ReadWrite.All"],
  "administrative_unit_roles": [...],
  "requires_terraform_state_access": [...]
}
```

## Configuration Properties

### GitHub Section

| Property                 | Type    | Required | Default  | Description                                   |
| ------------------------ | ------- | -------- | -------- | --------------------------------------------- |
| `description`            | string  | Yes      | -        | GitHub repository description                 |
| `topics`                 | array   | Yes      | -        | GitHub repository topics                      |
| `visibility`             | string  | No       | `public` | Repository visibility (`public` or `private`) |
| `has_downloads`          | boolean | No       | `false`  | Enable downloads section                      |
| `has_issues`             | boolean | No       | `true`   | Enable issues tracking                        |
| `has_projects`           | boolean | No       | `false`  | Enable projects board                         |
| `has_wiki`               | boolean | No       | `false`  | Enable wiki                                   |
| `auto_init`              | boolean | No       | `false`  | Create an initial README commit for a new repository |
| `is_template`            | boolean | No       | `false`  | Mark the managed GitHub repository as a template |
| `add_sonarcloud_secrets` | boolean | No       | `false`  | Project the existing Key Vault-backed Sonar token to Actions and Dependabot, including explicit policy-only opt-ins |
| `add_nuget_environment`  | boolean | No       | `false`  | Create NuGet publishing environment           |
| `github_app.enabled`     | boolean | No       | `false`  | Broker the organization-owned GitHub App credentials into the repository |
| `github_app.app_id`      | string  | When enabled | -     | GitHub App ID exposed as the `GH_APP_ID` repository variable |
| `github_app.installation_id` | string | When enabled | - | App installation ID exposed as the `GH_APP_INSTALLATION_ID` repository variable |
| `manage_repository`      | boolean | No       | `true`   | Manage repository lifecycle/settings; set `false` for policy-only catalog entries |
| `repository_analysis` | object | Non-`xi-*` catalog rows | - | Validated source profile, scanner/build recipe and analysis cadence, or explicit applicability exemption |
| `repository_standards` | object | No | - | Optional bounded exceptions for centrally managed repository standards; profile selection is derived from `repository_analysis` |
| `repository_policy.copilot_code_review.enabled` | boolean | No | `true` | Enroll the repository in the automatic Copilot review baseline |
| `repository_policy.copilot_code_review.exception_reason` | string | No | - | Required explanation when automatic review is explicitly disabled |

When `github_app.enabled` is true, Terraform also writes the Key Vault-backed
App private key to the repository Actions secret `GH_APP_PEM`. Workflows should
mint short-lived installation tokens and request only the permissions needed
for that operation; they must not expose or persist the private key.

Dedicated service identities use `github.runtime_apps`, not the shared CI key.
See [Runtime GitHub Apps](runtime-github-apps.md) for the manifest bootstrap,
exact repository-scope verification, direct workload Key Vault storage and
non-secret registration metadata. Incomplete registrations create no Actions
variables; private keys are never imported into Terraform state.

The public `actions` policy entry opts into the existing Sonar token broker as a
prerequisite for its repository-owned CI analysis replacement. This does not create
a credential, purchase a plan, import the repository, change visibility, enable a
new analyzer or disable Automatic Analysis. The owning analysis workstream must
separately accept and govern the caller and provider-method cutover.

### Repository analysis policy

`github.repository_analysis` is the catalog authority for the estate analysis contract.
It contains `profile` (`repository-analysis-v1`, actual source languages, Sonar selection
and optional reasoned exemption), `sonar` (scanner/build declarations or `null`) and
`cadence` (daily freshness, a 168-hour maximum full-rescan age and exact-revision,
force-capable, default-branch-only dispatch). Exemptions require a kind, reason and
re-evaluation condition and retain `sonar`/`cadence: null`.

Terraform validates every non-`xi-*` row before creating analysis variables. It projects
`REPOSITORY_ANALYSIS_PROFILE` and `REPOSITORY_ANALYSIS_CADENCE` only to applicable
repositories; substantive public Sonar targets also receive
`REPOSITORY_ANALYSIS_SONAR_RECIPE` and `REPOSITORY_ANALYSIS_BUILD`. SDK selections,
Framework absent-test policy, original CMake arguments and static-site non-testing
dispositions remain declared, not inferred from successful commands.

These variables contain configuration, never credentials, source excerpts or findings.
Private repositories select permitted local analysis and no public Sonar recipe.
Runtime selection must still recheck live visibility and execution/publication entitlement;
a catalog visibility value is not authorization. Exempt and excluded repositories receive
no analysis-variable writes, and policy-only entries are not lifecycle-imported.

Projection does not install a caller, activate a scanner, change provider methods, modify
rulesets, merge identity or deployment triggers, or claim current analysis acceptance.
The owning alignment workstream separately governs immutable caller adoption and bootstrap.
No new Azure identity, RBAC, subscription, environment or cost-bearing resource is needed.

### Repository standards policy

Applicable non-`xi-*` repository analysis profiles receive one
`REPOSITORY_STANDARDS` Actions variable. Analysis exemptions receive no standards
variable. The JSON contract is `repository-standards-v1` with a `managedFiles.checkov`
entry at `checkov-v1`.

Every applicable repository receives the `base` profile. Repositories whose declared
analysis languages include `terraform` or `bicep` additionally receive, in order,
`cost-optimised`, `public-endpoints`, `app-service-standard`, and
`central-observability`. Workload JSON cannot replace this profile selection.

Exceptional generated content may declare only
`github.repository_standards.checkov.exceptions`. Each list item must contain exactly
`rule` and `reason`. The only approved rules are `CKV_OPENAPI_21` and `CKV_SECRET_6`.
The trimmed reason must contain 10 to 600 characters without any U+0000-U+001F
C0 control (including tabs and line breaks), U+0085, U+2028, or U+2029.
Exceptions are sorted deterministically before projection.

This stack declares desired state only. It does not install or activate the separate
platform-devex reconciliation workflow; that behavior becomes active only after its
own implementation is merged and deployed.

### Repository policy defaults

Cataloged repositories receive the automatic Copilot review baseline by
default. The baseline adds `copilot_code_review` to `main-protection` with
`review_draft_pull_requests = false` and `review_on_push = false`, so Copilot
reviews once when a pull request becomes ready for review. If an enrolled
repository has no `main-protection` ruleset, Terraform creates a minimal
ruleset targeting `~DEFAULT_BRANCH` that contains only the Copilot rule.

Set `repository_policy.copilot_code_review.enabled` to `false` for archived,
empty, external/upstream, generated/documentation-only, or otherwise
exceptional repositories. Include `exception_reason` so the decision remains
auditable. Do not add a repository-only catalog entry merely to broaden
platform-workloads ownership; entries must be approved for central policy
management.

### Repository onboarding decisions

Before adding a definition:

1. Use an environment-backed workload only when this stack must create workload
   identity, integration, RBAC, or state resources.
2. Use a managed repository-only definition when Terraform should create and
   retain the repository but the repository is data-only or has no Azure
   environment.
3. Use a policy-only definition only for an existing repository whose lifecycle
   and general settings must remain outside this stack.
4. Record operator access and operational ownership in the target repository;
   this catalog does not manage collaborators or grant access to platform
   namespaces.

`platform-baremetal-ns512615` is the current managed repository-only pattern:
it is a private, data-only delegated-operations repository. Its lack of
`environments` prevents accidental creation of workload identities or Azure
infrastructure.

### Environment Section

| Property                          | Type    | Required | Description                                                                                                            |
| --------------------------------- | ------- | -------- | ---------------------------------------------------------------------------------------------------------------------- |
| `name`                            | string  | Yes      | Environment name (e.g., `Development`, `Production`)                                                                   |
| `subscription`                    | string  | Yes      | Subscription alias (e.g., `sub-visualstudio-enterprise`)                                                               |
| `connect_to_github`               | boolean | No       | Create GitHub environment and OIDC federation                                                                          |
| `container_registry_name`         | string  | No       | Project the reviewed registry name as `WORKLOAD_ACR_NAME` for an OIDC image publisher; registry RBAC remains owned by `platform-registry` |
| `configure_for_terraform`         | boolean | No       | Create Terraform state storage resources                                                                               |
| `add_deploy_script_identity`      | boolean | No       | Create managed identity for deployment scripts                                                                         |
| `role_assignments`                | object  | No       | Azure RBAC role assignments (roles, RBAC admin rules)                                                                  |
| `directory_roles`                 | array   | No       | Entra ID directory roles                                                                                               |
| `graph_api_permissions`           | array   | No       | Microsoft Graph application permissions to assign (e.g., AppRoleAssignment.ReadWrite.All, Application.Read.All)        |
| `administrative_unit_roles`       | array   | No       | Entra ID roles scoped to the workload Administrative Unit (e.g., Groups Administrator)                                 |
| `requires_terraform_state_access` | array   | No       | Workload state dependencies as names for the same environment or objects with explicit `workload` and `environment`    |
| `cloudflare_tokens`               | array   | No       | Cloudflare API tokens to create and inject as GitHub environment secrets (see [Cloudflare Tokens](#cloudflare-tokens)) |

### Role Assignments

Environment-level `role_assignments`:

```json
{
  "assigned_roles": [
    { "roles": ["Contributor", "Key Vault Secrets Officer"] },
    { "scope": "/subscriptions/.../resourceGroups/rg-foo", "roles": ["DNS Zone Contributor"] }
  ],
  "rbac_admin_roles": [
    { "allowed_roles": ["Key Vault Secrets User"] }
  ]
}
```

- If `scope` is omitted, the environment `subscription` is used.
- A `Reader` assignment is automatically added on the environment subscription; if a role already targets that scope, `Reader` is merged into its roles.
- `assigned_roles.roles` accept any Azure RBAC role name.
- `graph_api_permissions` are applied to the workload service principal (and deploy script identity when enabled) against Microsoft Graph; values must match Graph app role values such as `AppRoleAssignment.ReadWrite.All` or `Application.Read.All`.
- Scope input options (case-insensitive prefixes):
  - Raw ARM IDs starting with `/` are passed through as-is (e.g., `/providers/Microsoft.Management/managementGroups/alz`, `/subscriptions/.../resourceGroups/...`).
  - `sub:<alias>` resolves to a subscription from `var.subscriptions` (e.g., `sub:sub-visualstudio-enterprise`).
  - `/subscriptions/...` uses a raw ARM ID (any level: subscription, RG, or resource).
  - `workload:<workload>/<Environment>` targets another workload environment’s subscription (e.g., `workload:portal-core/Production`).
  - `workload-rg:<workload>/<Environment>/<rg-name>/<location>` targets a workload resource group after templating (e.g., `workload-rg:portal-core/Production/rg-portal-core-prd-app-uksouth`).
  - Bare values continue to support existing aliases or ARM IDs for backward compatibility.
- `rbac_admin_roles.allowed_roles` list the roles that the workload principal may assign; scope resolution matches `assigned_roles`.
- Assignments apply to the workload service principal and, when `add_deploy_script_identity` is enabled, also to the deploy script identity.

Sitewatch's Flex Consumption runtime requires `Storage Blob Data Owner` on its
own host storage account. Its CI delegation allows that role alongside the
existing blob contributor, queue contributor and secrets reader roles, only
within its existing Development and regional Production resource groups.
The owning workload stack creates the storage-scoped runtime assignment; this
catalog allowance is not a direct data-plane grant or subscription delegation.

`requires_terraform_state_access` entries use the current environment by default:

```json
"requires_terraform_state_access": [
  "platform-monitoring",
  {
    "workload": "platform-registry",
    "environment": "Production"
  }
]
```

Use the object form only for an intentional cross-environment state dependency. Both forms grant `Storage Blob Data Reader` on the target workload environment's Terraform state storage account.

Resource group `role_assignments` follow the same shape inside each `resource_groups` entry. If `scope` is omitted for a resource group role assignment, the resource group ID is used by default.

### Cloudflare Tokens

Environment-level `cloudflare_tokens` create scoped Cloudflare API tokens and inject them as GitHub environment secrets.
An optional `secret_name` selects a separate destination (default
`CLOUDFLARE_API_KEY`); destinations must be unique within an environment. This
allows separate deployment and runtime tokens without broadening an existing
credential or overwriting it:

```json
{
  "cloudflare_tokens": [
    {
      "name_suffix": "cert-rotation",
      "policies": [
        {
          "permission_groups": ["DNS Write", "Zone Read"],
          "zone": "example.com"
        }
      ]
    }
  ]
}
```

- Each token is created with name `spn-{workload}-{env}-{name_suffix}`.
- The token value is injected as a GitHub environment secret named `CLOUDFLARE_API_KEY`.
- `permission_groups` must be valid Cloudflare permission group names for the selected resource scope.
- `zone` (single domain) or `zones` (array of domains) selects the Cloudflare zone(s) the policy applies to. Prefer `zones` to group many domains into one policy — Cloudflare limits a token to **10 policies**, so one policy per domain does not scale.
- Account-level permissions instead use `account_from_zone`: the name of an existing zone whose account is discovered at plan time. The policy grants only its named permission groups on that account, not zone permissions or access to other accounts. Use exactly one of `zone`, `zones`, or `account_from_zone` per policy; every policy in a token must resolve to the same account.
- Load balancers require a zone-scoped `Load Balancers Write` policy; their monitors and pools require a separate account-scoped `Load Balancing: Monitors and Pools Write` policy. These are not billing permissions, and provisioning a token does not activate a subscription or change DNS. Account scope covers all monitors and pools in that account, so do not combine unrelated account permissions into the policy.
- All policies use `allow` effect by convention.
- The environment must have `connect_to_github: true` for the secret to be injected.
- Requires `CLOUDFLARE_API_KEY` and `CLOUDFLARE_EMAIL` GitHub environment secrets on platform-workloads (see [prerequisites](prerequisites.md)).

## Examples

See `terraform/workloads/{platform,portal,geo-location}/` for production configurations.
