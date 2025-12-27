# Architecture

## System Design

**Pattern**: JSON workload definitions → `fileset()` discovery → Terraform generates Azure AD, GitHub, and Azure DevOps resources.

**Core Flow**:
```
terraform/workloads/**/*.json (excluding examples/)
  ↓ fileset() in workloads.load.tf
  ↓ jsondecode() + flatten()
  ↓ for_each loops
  ├→ Azure AD: App registrations + SPNs + OIDC federation
  ├→ GitHub: Repos + environments + variables
  ├→ Azure DevOps: Service connections + environments + variable groups
  └→ Azure RBAC: Role assignments (subscription aliases or ARM IDs)
```

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
**Azure DevOps**: Dynamic from `azuredevops_serviceendpoint_azurerm.workload[].workload_identity_federation_subject`

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

**OIDC over Secrets**: Eliminates secret rotation. Workload identity federation for both GitHub and Azure DevOps.

**Conditional Resources via `if` in for_each**: Files named `azure-workloads.if-{feature}.tf` contain resources gated by flags (`connect_to_github`, `configure_for_terraform`, etc.).

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
