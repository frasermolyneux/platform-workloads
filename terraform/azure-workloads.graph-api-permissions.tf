data "azuread_application_published_app_ids" "well_known" {}

resource "azuread_service_principal" "microsoft_graph" {
  client_id    = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
  use_existing = true
}

locals {
  workload_graph_api_permissions = flatten([
    for environment in local.workload_environments : [
      for permission in distinct(try(environment.graph_api_permissions, [])) : {
        assignment_key             = format("%s-%s", environment.key, permission)
        workload_environment_key   = environment.key
        app_role_value             = permission
        app_role_id                = azuread_service_principal.microsoft_graph.app_role_ids[permission]
        add_deploy_script_identity = environment.add_deploy_script_identity
      }
    ]
  ])
}

resource "azuread_app_role_assignment" "workload_graph_api" {
  for_each = { for entry in local.workload_graph_api_permissions : entry.assignment_key => entry }

  app_role_id         = each.value.app_role_id
  principal_object_id = azuread_service_principal.workload[each.value.workload_environment_key].object_id
  resource_object_id  = azuread_service_principal.microsoft_graph.object_id
}

resource "azuread_app_role_assignment" "workload_graph_api_deploy_script" {
  for_each = { for entry in local.workload_graph_api_permissions : entry.assignment_key => entry if entry.add_deploy_script_identity }

  app_role_id         = each.value.app_role_id
  principal_object_id = azurerm_user_assigned_identity.workload_deploy_script[each.value.workload_environment_key].principal_id
  resource_object_id  = azuread_service_principal.microsoft_graph.object_id
}
