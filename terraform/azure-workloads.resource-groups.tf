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
          role_assignments         = try(resource_group.role_assignments, [])
          rbac_administrator_roles = try(resource_group.rbac_administrator_roles, [])
          tags = merge(var.tags, {
            Workload    = environment.workload_name
            Environment = environment.environment_name
          })
        }
      ]
    ]
  ])
}

locals {
  workload_environment_resource_group_role_assignments = flatten([
    for resource_group in local.workload_environment_resource_groups : [
      for role_definition in resource_group.role_assignments : {
        key                      = format("%s-%s", resource_group.key, lower(role_definition))
        workload_environment_key = resource_group.workload_environment_key
        resource_group_key       = resource_group.key
        role_definition_name     = role_definition
      }
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

resource "azurerm_role_assignment" "workload_resource_group" {
  for_each = { for each in local.workload_environment_resource_group_role_assignments : each.key => each }

  scope                = azapi_resource.workload_resource_group[each.value.resource_group_key].id
  role_definition_name = each.value.role_definition_name
  principal_id         = azuread_service_principal.workload[each.value.workload_environment_key].object_id
}
