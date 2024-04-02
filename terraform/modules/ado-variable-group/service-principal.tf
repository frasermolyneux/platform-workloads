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
