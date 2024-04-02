resource "azuread_application" "app" {
  display_name = format("spn-%s-%s-ado-kv", lower(var.workload_name), lower(var.environment_name))

  owners = [
    data.azuread_client_config.current.object_id
  ]

  sign_in_audience = "AzureADMyOrg"
}

resource "azuread_service_principal" "sp" {
  client_id                    = azuread_application.app.client_id
  app_role_assignment_required = false

  owners = [
    data.azuread_client_config.current.object_id
  ]
}

resource "azuread_application_password" "pw" {
  display_name   = format("azdo-%s-%s", lower(var.workload_name), lower(var.environment_name))
  application_id = azuread_application.app.id

  rotate_when_changed = {
    rotation = time_rotating.rotate.id
  }
}

resource "azuredevops_serviceendpoint_azurerm" "workload" {
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
