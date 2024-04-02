// Need to add at least one secret into the vault
resource "azurerm_key_vault_secret" "enviroment_name_secret" {
  name         = "environment-name"
  value        = var.environment_name
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.deploy_principal_workload_key_vault_secrets_officer
  ]
}
