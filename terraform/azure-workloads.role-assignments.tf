locals {
  workload_role_assignments = flatten([
    for role_assignment_key, workload_environment in local.workload_environments : [
      for role_assignment in workload_environment.role_assignments : [
        for role_definition in role_assignment.role_definitions : {
          role_assignment_key        = format("%s-%s-%s", workload_environment.key, role_assignment.role_definition_name, role_assignment.scope)
          workload_environment_key   = workload_environment.key
          add_deploy_script_identity = workload_environment.add_deploy_script_identity
          scope                      = role_assignment.scope
          role_definition_name       = role_definition
        }
      ]
    ]
  ])
}

resource "azurerm_role_assignment" "workload" {
  for_each = { for each in local.workload_role_assignments : each.role_assignment_key => each }

  scope                = data.azurerm_subscription.subscriptions[each.value.scope].id
  role_definition_name = each.value.role_definition_name
  principal_id         = azuread_service_principal.workload[each.value.workload_environment_key].object_id
}

resource "azurerm_role_assignment" "workload_deploy_script" {
  for_each = { for each in local.workload_role_assignments : each.role_assignment_key => each if each.add_deploy_script_identity }

  scope                = data.azurerm_subscription.subscriptions[each.value.scope].id
  role_definition_name = each.value.role_definition_name
  principal_id         = azurerm_user_assigned_identity.workload_deploy_script[each.value.workload_environment_key].principal_id
}
