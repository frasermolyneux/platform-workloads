# Workload Configuration Reference

## Schema Overview

Workload JSON files in `terraform/workloads/{category}/` drive infrastructure creation. Each file generates:
- Azure AD service principal with OIDC federation
- GitHub repository + environments
- Azure DevOps service connections + variable groups
- RBAC assignments at specified scopes
- Terraform state storage (optional)

## JSON Structure

```json
{
  "name": "workload-name",
  "github": {
    "description": "Description of the workload",
    "topics": ["azure", "terraform", "devops"],
    "visibility": "public",
    "has_downloads": false,
    "has_issues": false,
    "has_projects": false,
    "has_wiki": false,
    "add_sonarcloud_secrets": false,
    "add_nuget_environment": false
  },
  "environments": [...]
}
```

### Environment Configuration

```json
{
  "name": "Development",
  "subscription": "sub-visualstudio-enterprise",
  "devops_project": "ProjectName",
  "connect_to_github": true,
  "connect_to_devops": true,
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
| `has_issues`             | boolean | No       | `false`  | Enable issues tracking                        |
| `has_projects`           | boolean | No       | `false`  | Enable projects board                         |
| `has_wiki`               | boolean | No       | `false`  | Enable wiki                                   |
| `add_sonarcloud_secrets` | boolean | No       | `false`  | Add SonarCloud token secrets                  |
| `add_nuget_environment`  | boolean | No       | `false`  | Create NuGet publishing environment           |

### Environment Section

| Property                          | Type    | Required | Description                                                                                                     |
| --------------------------------- | ------- | -------- | --------------------------------------------------------------------------------------------------------------- |
| `name`                            | string  | Yes      | Environment name (e.g., `Development`, `Production`)                                                            |
| `subscription`                    | string  | Yes      | Subscription alias (e.g., `sub-visualstudio-enterprise`)                                                        |
| `devops_project`                  | string  | No       | Azure DevOps project name                                                                                       |
| `connect_to_github`               | boolean | No       | Create GitHub environment and OIDC federation                                                                   |
| `connect_to_devops`               | boolean | No       | Automatically set if `devops_project` is specified                                                              |
| `configure_for_terraform`         | boolean | No       | Create Terraform state storage resources                                                                        |
| `add_deploy_script_identity`      | boolean | No       | Create managed identity for deployment scripts                                                                  |
| `role_assignments`                | object  | No       | Azure RBAC role assignments (roles, RBAC admin rules)                                                           |
| `directory_roles`                 | array   | No       | Entra ID directory roles                                                                                        |
| `graph_api_permissions`           | array   | No       | Microsoft Graph application permissions to assign (e.g., AppRoleAssignment.ReadWrite.All, Application.Read.All) |
| `administrative_unit_roles`       | array   | No       | Entra ID roles scoped to the workload Administrative Unit (e.g., Groups Administrator)                          |
| `requires_terraform_state_access` | array   | No       | Workload names requiring read access to this workload's Terraform state                                         |

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
  - `sub:<alias>` resolves to a subscription from `var.subscriptions` (e.g., `sub:sub-visualstudio-enterprise`).
  - `/subscriptions/...` uses a raw ARM ID (any level: subscription, RG, or resource).
  - `workload:<workload>/<Environment>` targets another workload environment’s subscription (e.g., `workload:portal-core/Production`).
  - `workload-rg:<workload>/<Environment>/<rg-name>/<location>` targets a workload resource group after templating (e.g., `workload-rg:portal-core/Production/rg-portal-core-prd-app-uksouth`).
  - Bare values continue to support existing aliases or ARM IDs for backward compatibility.
- `rbac_admin_roles.allowed_roles` list the roles that the workload principal may assign; scope resolution matches `assigned_roles`.
- Assignments apply to the workload service principal and, when `add_deploy_script_identity` is enabled, also to the deploy script identity.

Resource group `role_assignments` follow the same shape inside each `resource_groups` entry. If `scope` is omitted for a resource group role assignment, the resource group ID is used by default.

## Examples

See `terraform/workloads/{platform,portal,geo-location}/` for production configurations.
