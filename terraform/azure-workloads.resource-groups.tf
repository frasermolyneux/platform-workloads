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
          role_assignments = {
            default_scope = try(resource_group.role_assignments.scope, null)
            assigned_roles = [
              for assignment in try(resource_group.role_assignments.assigned_roles, []) : {
                scope = try(coalesce(try(assignment.scope, null), try(resource_group.role_assignments.scope, null)), null)
                roles = distinct(try(assignment.roles, []))
              }
            ]
            rbac_admin_roles = [
              for assignment in try(resource_group.role_assignments.rbac_admin_roles, []) : {
                scope         = try(coalesce(try(assignment.scope, null), try(resource_group.role_assignments.scope, null)), null)
                allowed_roles = distinct(try(assignment.allowed_roles, []))
              }
              if length(distinct(compact(flatten([try(assignment.allowed_roles, [])])))) > 0
            ]
          }
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
      for assignment in resource_group.role_assignments.assigned_roles : [
        for role_definition in assignment.roles : {
          key                      = format("%s-%s", resource_group.key, lower(role_definition))
          workload_environment_key = resource_group.workload_environment_key
          resource_group_key       = resource_group.key
          role_definition_name     = role_definition
          scope                    = coalesce(assignment.scope, resource_group.role_assignments.default_scope, azapi_resource.workload_resource_group[resource_group.key].id)
        }
      ]
      if length(assignment.roles) > 0
    ]
  ])
}

locals {
  workload_environment_resource_groups_map = {
    for resource_group in local.workload_environment_resource_groups :
    resource_group.key => resource_group
  }
}

resource "azapi_resource" "workload_resource_group" {
  for_each = { for each in local.workload_environment_resource_groups : each.key => each }

  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  name      = each.value.name
  parent_id = data.azurerm_subscription.subscriptions[each.value.subscription].id
  location  = each.value.location

  tags = each.value.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_role_assignment" "workload_resource_group" {
  for_each = { for each in local.workload_environment_resource_group_role_assignments : each.key => each }

  scope                = coalesce(each.value.scope, local.workload_environment_resource_groups_map[each.value.resource_group_key].role_assignments.default_scope, azapi_resource.workload_resource_group[each.value.resource_group_key].id)
  role_definition_name = each.value.role_definition_name
  principal_id         = azuread_service_principal.workload[each.value.workload_environment_key].object_id
}
