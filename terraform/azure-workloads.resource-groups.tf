// Create per-environment resource group definitions based on workload metadata.
locals {
  workload_environment_resource_groups = flatten([
    for environment in local.workload_environments : [
      for location in environment.locations : [
        for resource_group in coalesce(environment.resource_groups, []) : {
          key                      = format("%s-%s-%s", environment.key, location, lower(replace(replace(replace(resource_group.name, "{workload}", lower(environment.workload_name)), "{env}", lower(environment.environment_tag)), "{location}", location)))
          workload_environment_key = environment.key
          workload_name            = environment.workload_name
          environment_name         = environment.environment_name
          environment_tag          = environment.environment_tag
          subscription             = environment.subscription
          location                 = location
          name                     = lower(replace(replace(replace(resource_group.name, "{workload}", lower(environment.workload_name)), "{env}", lower(environment.environment_tag)), "{location}", location))
          role_assignments = {
            assigned_roles = [
              for assignment in try(resource_group.role_assignments.assigned_roles, []) : {
                scope = try(assignment.scope, null)
                roles = distinct(try(assignment.roles, []))
              }
            ]
            rbac_admin_roles = [
              for assignment in try(resource_group.role_assignments.rbac_admin_roles, []) : {
                scope         = try(assignment.scope, null)
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
          scope_value              = coalesce(assignment.scope, azapi_resource.workload_resource_group[resource_group.key].id)
          resolved_scope = (
            assignment.scope == null
            ? azapi_resource.workload_resource_group[resource_group.key].id
            : (
              startswith(lower(assignment.scope), "/subscriptions/")
              ? assignment.scope
              : (
                startswith(lower(assignment.scope), "sub:")
                ? data.azurerm_subscription.subscriptions[replace(lower(assignment.scope), "sub:", "")].id
                : (
                  startswith(lower(assignment.scope), "workload:")
                  ? local.workload_environment_subscription_id_by_name[replace(lower(assignment.scope), "workload:", "")]
                  : (
                    startswith(lower(assignment.scope), "workload-rg:")
                    ? local.workload_resource_group_scope_map[replace(lower(assignment.scope), "workload-rg:", "")]
                    : data.azurerm_subscription.subscriptions[assignment.scope].id
                  )
                )
              )
            )
          )
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

locals {
  workload_resource_group_scope_map = {
    for resource_group in local.workload_environment_resource_groups :
    lower(format(
      "%s/%s/%s/%s",
      resource_group.workload_name,
      resource_group.environment_name,
      resource_group.name,
      resource_group.location
    )) => azapi_resource.workload_resource_group[resource_group.key].id
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

  scope                = coalesce(each.value.resolved_scope, each.value.scope_value, azapi_resource.workload_resource_group[each.value.resource_group_key].id)
  role_definition_name = each.value.role_definition_name
  principal_id         = azuread_service_principal.workload[each.value.workload_environment_key].object_id
}

resource "azurerm_role_assignment" "workload_plan_resource_group" {
  for_each = { for each in local.workload_environment_resource_group_role_assignments : each.key => each }

  scope                = coalesce(each.value.resolved_scope, each.value.scope_value, azapi_resource.workload_resource_group[each.value.resource_group_key].id)
  role_definition_name = each.value.role_definition_name
  principal_id         = azuread_service_principal.workload_plan[each.value.workload_environment_key].object_id
}
