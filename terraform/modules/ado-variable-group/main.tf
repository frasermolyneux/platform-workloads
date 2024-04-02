resource "azurerm_resource_group" "workload" {
  name     = format("rg-ado-%s-%s-%s-%s", var.workload_name, var.environment, var.location, var.instance)
  location = var.location

  tags = merge(var.tags, { Workload = var.workload_name, Environment = var.environment })
}
