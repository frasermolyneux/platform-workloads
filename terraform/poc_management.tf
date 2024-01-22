// This principal is used by the https://github.com/frasermolyneux-poc/.github repository which manages PoCs within the Molyneux.IO tenant.
resource "azuread_application" "poc" {
  display_name = "spn-frasermolyneux-poc-production"

  owners = [
    data.azuread_client_config.current.object_id
  ]

  sign_in_audience = "AzureADMyOrg"
}

resource "azuread_service_principal" "poc" {
  client_id                    = azuread_application.poc.client_id
  app_role_assignment_required = false

  owners = [
    data.azuread_client_config.current.object_id
  ]
}

resource "azuread_application_federated_identity_credential" "poc" {
  application_id = azuread_application.poc.id
  display_name   = "github-frasermolyneux-poc-production"
  description    = "GitHub Actions"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:frasermolyneux-poc/.github:environment:Production"
}

resource "azurerm_role_assignment" "poc_owner" {
  scope                = data.azurerm_subscription.subscriptions["sub-visualstudio-enterprise"].id
  role_definition_name = "Owner"
  principal_id         = azuread_service_principal.poc.object_id
}

resource "azurerm_role_assignment" "poc_keyvault_administrator" {
  scope                = data.azurerm_subscription.subscriptions["sub-visualstudio-enterprise"].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azuread_service_principal.poc.object_id
}

resource "azurerm_role_assignment" "poc_storage_blob_data_owner" {
  scope                = data.azurerm_subscription.subscriptions["sub-visualstudio-enterprise"].id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azuread_service_principal.poc.object_id
}
