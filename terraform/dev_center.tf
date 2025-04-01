locals {
  environment_types = [
    "Development",
    "Production",
  ]
}

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

resource "azapi_resource" "environment_type" {
  for_each = { for each in local.environment_types : each => each }

  type      = "Microsoft.DevCenter/devcenters/environmentTypes@2025-02-01"
  parent_id = azapi_resource.dev_center.id

  name = each.value

  tags = {
    Environment = each.value
  }

  body = {
    properties = {
      displayName = each.value
    }
  }
}

resource "azapi_resource" "workload" {
  for_each = { for each in var.workloads : each.name => each if each.create_dev_center_project }

  type      = "Microsoft.DevCenter/projects@2025-02-01"
  parent_id = azurerm_resource_group.rg.id

  name     = each.value.name
  location = azurerm_resource_group.rg.location

  tags = merge(var.tags, { Workload = each.value.name })

  body = {
    properties = {
      description = "Project for workload ${each.value.name}"
      devCenterId = azapi_resource.dev_center.id
      displayName = each.value.name
    }
  }
}

resource "azapi_resource" "project_environment" {
  for_each = { for each in local.workload_environments : each.key => each if each.create_dev_center_project }

  type      = "Microsoft.DevCenter/projects/environmentTypes@2025-02-01"
  parent_id = azapi_resource.workload[each.value.workload_name].id

  name     = azapi_resource.environment_type[each.value.environment_name].name
  location = azurerm_resource_group.rg.location

  tags = merge(
    azapi_resource.environment_type[each.value.environment_name].tags,
    { Workload = each.value.workload_name }
  )

  body = {
    properties = {
      deploymentTargetId = data.azurerm_subscription.subscriptions[each.value.subscription].id
      displayName        = azapi_resource.environment_type[each.value.environment_name].name
      status             = "Enabled"
    }
  }

  identity {
    type = "SystemAssigned"
  }
}
