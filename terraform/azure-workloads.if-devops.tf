resource "azuread_application_password" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  display_name   = format("azdo-%s-%s", lower(each.value.workload_name), lower(each.value.environment_name))
  application_id = azuread_application.workload[each.key].id

  rotate_when_changed = {
    rotation = time_rotating.rotate.id
  }
}

resource "azuredevops_environment" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  project_id = azuredevops_project.project[each.value.devops_project].id
  name       = each.key
}

resource "azuredevops_pipeline_authorization" "workload_environment" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  project_id  = azuredevops_project.project[each.value.devops_project].id
  resource_id = azuredevops_environment.workload[each.key].id

  type = "environment"
}

resource "azuredevops_serviceendpoint_azurerm" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  project_id            = azuredevops_project.project[each.value.devops_project].id
  service_endpoint_name = azuread_application.workload[each.key].display_name
  description           = "Managed By platform-workloads"

  credentials {
    serviceprincipalid  = azuread_service_principal.workload[each.key].application_id
    serviceprincipalkey = azuread_application_password.workload[each.key].value
  }

  azurerm_spn_tenantid      = "e56a6947-bb9a-4a6e-846a-1f118d1c3a14"
  azurerm_subscription_id   = var.subscriptions[each.value.subscription].subscription_id
  azurerm_subscription_name = var.subscriptions[each.value.subscription].name
}

resource "azuredevops_pipeline_authorization" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  project_id  = azuredevops_project.project[each.value.devops_project].id
  resource_id = azuredevops_serviceendpoint_azurerm.workload[each.key].id

  type = "endpoint"
}
