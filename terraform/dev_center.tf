resource "azurerm_dev_center" "dev_center" {
  name = local.dev_center_name

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = var.tags
}

resource "azurerm_dev_center_project" "workload" {
  for_each = { for each in var.workloads : each.name => each if each.create_dev_center_project }

  name = each.value.name

  dev_center_id = azurerm_dev_center.dev_center.id

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = merge(var.tags, { Workload = each.value.name })
}

resource "azurerm_dev_center_project_environment" "workload_env" {
  for_each = { for each in local.workload_environments : each.key => each if var.workloads[each.value.workload_name].create_dev_center_project }

  name                = each.value.environment_name
  project_name        = azurerm_dev_center_project.workload[each.value.workload_name].name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = merge(var.tags, { Workload = each.value.workload_name, Environment = each.value.environment_name })
}
