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
  "role_assignments": [...],
  "directory_roles": [...],
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

| Property                          | Type    | Required | Description                                                             |
| --------------------------------- | ------- | -------- | ----------------------------------------------------------------------- |
| `name`                            | string  | Yes      | Environment name (e.g., `Development`, `Production`)                    |
| `subscription`                    | string  | Yes      | Subscription alias (e.g., `sub-visualstudio-enterprise`)                |
| `devops_project`                  | string  | No       | Azure DevOps project name                                               |
| `connect_to_github`               | boolean | No       | Create GitHub environment and OIDC federation                           |
| `connect_to_devops`               | boolean | No       | Automatically set if `devops_project` is specified                      |
| `configure_for_terraform`         | boolean | No       | Create Terraform state storage resources                                |
| `add_deploy_script_identity`      | boolean | No       | Create managed identity for deployment scripts                          |
| `role_assignments`                | array   | No       | Azure RBAC role assignments                                             |
| `directory_roles`                 | array   | No       | Entra ID directory roles                                                |
| `requires_terraform_state_access` | array   | No       | Workload names requiring read access to this workload's Terraform state |

### Role Assignment Scopes

```json
{ "scope": "sub-alias or /subscriptions/.../resourceGroups/.../providers/...", "role_definitions": ["Role Name"] }
```

**Scope Resolution**:
- Subscription aliases (e.g., `sub-platform-strategic`) resolved via `data.azurerm_subscription`
- Full ARM resource IDs used directly
- Service principal AND deploy script identity (if enabled) receive assignments

## Examples

See `terraform/workloads/{platform,portal,geo-location}/` for production configurations.
