locals {
  workload_role_assignments = flatten([
    for role_assignment_key, workload_environment in local.workload_environments : [
      for role_assignment in workload_environment.role_assignments : [
        for role_definition in role_assignment.role_definitions : {
          role_assignment_key        = format("%s-%s-%s", workload_environment.key, role_definition, role_assignment.scope)
          workload_environment_key   = workload_environment.key
          add_deploy_script_identity = workload_environment.add_deploy_script_identity
          scope                      = role_assignment.scope
          role_definition_name       = role_definition
        }
      ]
    ]
  ])

  workload_role_assignment_scopes = {
    for role_assignment in local.workload_role_assignments : role_assignment.role_assignment_key => (
      startswith(role_assignment.scope, "/subscriptions/")
      ? role_assignment.scope
      : coalesce(
        lookup(local.workload_scope_catalog[role_assignment.workload_environment_key], role_assignment.scope, null),
        try(data.azurerm_subscription.subscriptions[role_assignment.scope].id, null)
      )
    )
  }
}

resource "azurerm_role_assignment" "workload" {
  for_each = { for each in local.workload_role_assignments : each.role_assignment_key => each }

  scope = local.workload_role_assignment_scopes[each.key]

  role_definition_name = each.value.role_definition_name
  principal_id         = azuread_service_principal.workload[each.value.workload_environment_key].object_id
}

resource "azurerm_role_assignment" "workload_deploy_script" {
  for_each = { for each in local.workload_role_assignments : each.role_assignment_key => each if each.add_deploy_script_identity }

  scope = local.workload_role_assignment_scopes[each.key]

  role_definition_name = each.value.role_definition_name
  principal_id         = azurerm_user_assigned_identity.workload_deploy_script[each.value.workload_environment_key].principal_id
}
