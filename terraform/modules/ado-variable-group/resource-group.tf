resource "azurerm_resource_group" "rg" {
  name     = format("rg-ado-%s-%s-%s-%s", var.workload_name, var.environment_tag, var.location, var.instance)
  location = var.location

  tags = local.tags
}
