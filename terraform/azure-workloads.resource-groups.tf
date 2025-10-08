// Create per-environment resource group definitions based on workload metadata.
locals {
  workload_environment_resource_groups = flatten([
    for environment in local.workload_environments : [
      for location in environment.locations : [
        for resource_group in coalesce(environment.resource_groups, []) : {
          key                      = format("%s-%s-%s", environment.key, location, lower(replace(replace(replace(resource_group.name, "{workload}", lower(environment.workload_name)), "{env}", lower(environment.environment_tag)), "{location}", location)))
          workload_environment_key = environment.key
          subscription             = environment.subscription
          location                 = location
          name                     = lower(replace(replace(replace(resource_group.name, "{workload}", lower(environment.workload_name)), "{env}", lower(environment.environment_tag)), "{location}", location))
          tags = merge(var.tags, {
            Workload    = environment.workload_name
            Environment = environment.environment_name
            Location    = upper(location)
          })
        }
      ]
    ]
  ])
}

resource "azapi_resource" "workload_resource_group" {
  for_each = { for each in local.workload_environment_resource_groups : each.key => each }

  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  name      = each.value.name
  parent_id = data.azurerm_subscription.subscriptions[each.value.subscription].id
  location  = each.value.location

  tags = each.value.tags
}
