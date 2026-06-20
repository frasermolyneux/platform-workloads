resource "azurerm_key_vault" "kv" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  tags = var.tags

  soft_delete_retention_days = 90
  purge_protection_enabled   = true
  rbac_authorization_enabled = true

  sku_name = "standard"

  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow"
  }
}

resource "azurerm_role_assignment" "deploy_principal_kv_role_assignment" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets" - This is a manually managed secret by design.
resource "azurerm_key_vault_secret" "github_app_pem" {
  # checkov:skip=CKV_AZURE_41: "Ensure that the expiration date is set on all secrets" - This is a manually managed secret by design.
  name         = "github-app-pem"
  value        = "placeholder"
  key_vault_id = azurerm_key_vault.kv.id

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_role_assignment.deploy_principal_kv_role_assignment]
}
