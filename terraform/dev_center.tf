//locals {
//  environment_types = [
//    "Development",
//    "Production",
//  ]
//}
//
//resource "azurerm_dev_center" "dev_center" {
//  name = local.dev_center_name
//
//  location            = azurerm_resource_group.rg.location
//  resource_group_name = azurerm_resource_group.rg.name
//
//  tags = var.tags
//}
resource "azapi_resource" "dev_center" {
  type      = "Microsoft.DevCenter/devcenters@2025-02-01"
  parent_id = azurerm_resource_group.rg.id

  name     = local.dev_center_name
  location = azurerm_resource_group.rg.location

  tags = var.tags

  body = {
    properties = {
      displayName = local.dev_center_name
    }
  }
}
//
//resource "azurerm_dev_center_environment_type" "environment" {
//  for_each = { for each in local.environment_types : each => each }
//
//  name          = each.value
//  dev_center_id = azurerm_dev_center.dev_center.id
//
//  tags = {
//    Environment = each.value
//  }
//}
//
//resource "azurerm_dev_center_project" "workload" {
//  for_each = { for each in var.workloads : each.name => each if each.create_dev_center_project }
//
//  name = each.value.name
//
//  dev_center_id = azurerm_dev_center.dev_center.id
//
//  location            = azurerm_resource_group.rg.location
//  resource_group_name = azurerm_resource_group.rg.name
//
//  tags = merge(var.tags, { Workload = each.value.name })
//}
//
//resource "azurerm_dev_center_project_environment_type" "project_environment" {
//  for_each = { for each in local.workload_environments : each.key => each if each.create_dev_center_project }
//
//  name     = azurerm_dev_center_environment_type.environment[each.value.environment_name].name
//  location = azurerm_resource_group.rg.location
//
//  dev_center_project_id = azurerm_dev_center_project.workload[each.value.workload_name].id
//  deployment_target_id  = data.azurerm_subscription.subscriptions[each.value.subscription].id
//
//  identity {
//    type = "SystemAssigned"
//  }
//
//  tags = merge(azurerm_dev_center_environment_type.environment[each.value.environment_name].tags, { Workload = each.value.workload_name })
//}
