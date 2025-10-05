locals {
  workload_rbac_administrator_map = {
    for environment in local.workload_environments :
    environment.key => [
      for entry in try(environment.rbac_administrator, []) : {
        workload_name          = environment.workload_name
        environment_name       = environment.environment_name
        service_principal_name = format("spn-%s-%s", lower(environment.workload_name), lower(environment.environment_name))
        scope_name             = entry.scope
        scope_id               = try(data.azurerm_subscription.subscriptions[entry.scope].id, entry.scope)
        subscription_id        = try(data.azurerm_subscription.subscriptions[entry.scope].subscription_id, null)
        allowed_roles          = try(entry.allowed_roles, [])
      }
    ]
    if length(try(environment.rbac_administrator, [])) > 0
  }

  workload_rbac_allowed_role_map = {
    for request in flatten([
      for environment in local.workload_environments : [
        for entry in try(environment.rbac_administrator, []) : [
          for role_name in try(entry.allowed_roles, []) : {
            key        = format("%s|%s", entry.scope, role_name)
            scope_name = entry.scope
            role_name  = role_name
          }
        ]
      ]
    ]) :
    request.key => {
      scope_name = request.scope_name
      role_name  = request.role_name
    }
  }

  workload_rbac_administrator_assignments = flatten([
    for environment in local.workload_environments : [
      for entry_index, entry in try(environment.rbac_administrator, []) : {
        assignment_key           = format("%s-%s-%d", environment.key, replace(entry.scope, "/", "-"), entry_index)
        workload_environment_key = environment.key
        scope_id                 = try(data.azurerm_subscription.subscriptions[entry.scope].id, entry.scope)
        principal_object_id      = azuread_service_principal.workload[environment.key].object_id
        allowed_role_keys = [
          for role_name in try(entry.allowed_roles, []) :
          format("%s|%s", entry.scope, role_name)
        ]
      }
      if length(try(entry.allowed_roles, [])) > 0
    ]
  ])
}

data "azurerm_role_definition" "workload_rbac_allowed" {
  for_each = local.workload_rbac_allowed_role_map

  name  = each.value.role_name
  scope = try(data.azurerm_subscription.subscriptions[each.value.scope_name].id, each.value.scope_name)
}

locals {
  role_definition_guid_pattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

  workload_rbac_allowed_role_guids = {
    for key, definition in data.azurerm_role_definition.workload_rbac_allowed :
    key => lower(
      element(
        distinct(
          compact([
            try(definition.role_definition_id, null),
            try(element(regexall(local.role_definition_guid_pattern, definition.id), 0), null)
          ])
        ),
        0
      )
    )
  }
}

resource "azurerm_role_assignment" "workload_rbac_administrator" {
  for_each = { for assignment in local.workload_rbac_administrator_assignments : assignment.assignment_key => assignment }

  scope                = each.value.scope_id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azuread_service_principal.workload[each.value.workload_environment_key].object_id

  condition_version = "2.0"
  condition = trimspace(<<EOT
(
  (
    !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
  )
  OR
  (
    @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${join(", ", [for role_key in each.value.allowed_role_keys : local.workload_rbac_allowed_role_guids[role_key]])}}
  )
)
AND
(
  (
    !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
  )
  OR
  (
    @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${join(", ", [for role_key in each.value.allowed_role_keys : local.workload_rbac_allowed_role_guids[role_key]])}}
  )
)
EOT
  )
}

output "workload_rbac_administrators" {
  value = local.workload_rbac_administrator_map
}
