resource "azuredevops_serviceendpoint_azurerm" "se" {
  project_id            = data.azuredevops_project.project[var.devops_project].id
  service_endpoint_name = azuread_application.app.display_name
  description           = "Managed By platform-workloads"

  credentials {
    serviceprincipalid  = azuread_service_principal.sp.application_id
    serviceprincipalkey = azuread_application_password.pw.value
  }

  azurerm_spn_tenantid      = data.azurerm_client_config.current.tenant_id
  azurerm_subscription_id   = var.subscriptions[var.subscription].subscription_id
  azurerm_subscription_name = var.subscriptions[var.subscription].name
}
