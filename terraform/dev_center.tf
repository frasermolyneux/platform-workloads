resource "azurerm_dev_center" "dev_center" {
  name = local.dev_center_name

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = var.tags
}
