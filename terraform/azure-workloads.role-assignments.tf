locals {
  workload_role_assignments = flatten([
    for role_assignment_key, workload_environment in local.workload_environments : [
      for role_assignment in workload_environment.role_assignments : {
        role_assignment_key      = format("%s-%s-%s", workload_environment.key, role_assignment.role_definition_name, role_assignment.scope)
        workload_environment_key = workload_environment.key
        scope                    = role_assignment.scope
        role_definition_name     = role_assignment.role_definition_name
      }
    ]
  ])
}

resource "azurerm_role_assignment" "workload" {
  for_each = { for each in local.workload_role_assignments : each.role_assignment_key => each }

  scope                = data.azurerm_subscription.subscriptions[each.value.scope].id
  role_definition_name = each.value.role_definition_name
  principal_id         = azuread_service_principal.workload[each.value.workload_environment_key].object_id
}
