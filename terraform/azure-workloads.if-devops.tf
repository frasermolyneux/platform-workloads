resource "azuread_application_federated_identity_credential" "devops_workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  application_id = azuread_application.workload[each.key].id
  display_name   = format("ado-%s-%s", lower(each.value.workload_name), lower(each.value.environment_name))
  description    = "Azure DevOps"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://vstoken.dev.azure.com/af603ba1-963b-4eea-962e-9f543ae9813d"
  subject        = "sc://frasermolyneux/${azuredevops_project.project[each.value.devops_project].name}/${azuread_application.workload[each.key].name}"
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

  project_id = azuredevops_project.project[each.value.devops_project].id

  service_endpoint_name                  = azuread_application.workload[each.key].display_name
  service_endpoint_authentication_scheme = "WorkloadIdentityFederation"

  description = "Managed By platform-workloads"

  credentials {
    serviceprincipalid = azuread_service_principal.workload[each.key].application_id
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
