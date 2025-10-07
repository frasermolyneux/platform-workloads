resource "azurerm_resource_group" "workload_environment" {
  for_each = { for each in local.workload_environments : each.key => each if each.create_resource_group }

  name     = format("rg-%s-%s", each.value.workload_name, each.value.environment_tag)
  location = var.location

  tags = merge(var.tags, { Workload = each.value.workload_name, Environment = each.value.environment_name })
}
