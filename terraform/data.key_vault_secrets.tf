data "azurerm_key_vault_secret" "sonarcloud_token" {
  name         = "sonarcloud-token"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.deploy_principal_kv_role_assignment
  ]
}

data "azurerm_key_vault_secret" "nuget_token" {
  name         = "nuget-token"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.deploy_principal_kv_role_assignment
  ]
}
