locals {
  // Environment-scoped RBAC roles (all values known at plan time)
  workload_rbac_allowed_role_map_env = {
    for request in distinct(flatten([
      for environment in local.workload_environments : [
        for entry in try(environment.role_assignments.rbac_admin_roles, []) : [
          for role_name in distinct(compact(flatten([
            try(entry.allowed_roles, [])
            ]))) : {
            key = format(
              "%s|%s",
              tostring(
                coalesce(try(entry.scope, null), environment.subscription) == null
                ? data.azurerm_subscription.subscriptions[environment.subscription].id
                : (
                  startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "/subscriptions/")
                  ? coalesce(try(entry.scope, null), environment.subscription)
                  : (
                    startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "sub:")
                    ? data.azurerm_subscription.subscriptions[replace(lower(coalesce(try(entry.scope, null), environment.subscription)), "sub:", "")].id
                    : (
                      startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload:")
                      ? local.workload_environment_subscription_id_by_name[replace(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload:", "")]
                      : (
                        startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload-rg:")
                        ? local.workload_resource_group_scope_map[replace(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload-rg:", "")]
                        : data.azurerm_subscription.subscriptions[coalesce(try(entry.scope, null), environment.subscription)].id
                      )
                    )
                  )
                )
              ),
              role_name
            )
            role_name = role_name
          }
        ]
      ]
    ])) :
    request.key => {
      role_name = request.role_name
    }
  }

  // Resource-group-scoped RBAC roles (scope IDs resolve after apply, but keys are fully known at plan time)
  workload_rbac_allowed_role_map_rg = {
    for request in flatten([
      for resource_group in local.workload_environment_resource_groups : [
        for entry in try(resource_group.role_assignments.rbac_admin_roles, []) : [
          for role_name in distinct(compact(flatten([try(entry.allowed_roles, [])]))) : {
            key = format(
              "%s|%s",
              tostring(
                coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id) == null
                ? azapi_resource.workload_resource_group[resource_group.key].id
                : (
                  startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "/subscriptions/")
                  ? coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)
                  : (
                    startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "sub:")
                    ? data.azurerm_subscription.subscriptions[replace(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "sub:", "")].id
                    : (
                      startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload:")
                      ? local.workload_environment_subscription_id_by_name[replace(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload:", "")]
                      : (
                        startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload-rg:")
                        ? local.workload_resource_group_scope_map[replace(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload-rg:", "")]
                        : data.azurerm_subscription.subscriptions[coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)].id
                      )
                    )
                  )
                )
              ),
              role_name
            )
            role_name = role_name
          }
        ]
      ]
    ]) :
    request.key => {
      role_name = request.role_name
    }
  }

  workload_rbac_allowed_role_map = merge(
    local.workload_rbac_allowed_role_map_env,
    local.workload_rbac_allowed_role_map_rg
  )

  workload_rbac_administrator_assignments = flatten(concat(
    [
      for environment in local.workload_environments : [
        for entry_index, entry in try(environment.role_assignments.rbac_admin_roles, []) : {
          assignment_key = format(
            "%s-%s-%d",
            environment.key,
            replace(coalesce(try(entry.scope, null), environment.subscription), "/", "-"),
            entry_index
          )
          workload_environment_key = environment.key
          scope_id = (
            coalesce(try(entry.scope, null), environment.subscription) == null
            ? data.azurerm_subscription.subscriptions[environment.subscription].id
            : (
              startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "/subscriptions/")
              ? coalesce(try(entry.scope, null), environment.subscription)
              : (
                startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "sub:")
                ? data.azurerm_subscription.subscriptions[replace(lower(coalesce(try(entry.scope, null), environment.subscription)), "sub:", "")].id
                : (
                  startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload:")
                  ? local.workload_environment_subscription_id_by_name[replace(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload:", "")]
                  : (
                    startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload-rg:")
                    ? local.workload_resource_group_scope_map[replace(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload-rg:", "")]
                    : data.azurerm_subscription.subscriptions[coalesce(try(entry.scope, null), environment.subscription)].id
                  )
                )
              )
            )
          )
          principal_object_id = azuread_service_principal.workload[environment.key].object_id
          allowed_role_keys = [
            for role_name in distinct(compact(flatten([
              try(entry.allowed_roles, [])
            ]))) :
            format(
              "%s|%s",
              tostring(
                coalesce(try(entry.scope, null), environment.subscription) == null
                ? data.azurerm_subscription.subscriptions[environment.subscription].id
                : (
                  startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "/subscriptions/")
                  ? coalesce(try(entry.scope, null), environment.subscription)
                  : (
                    startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "sub:")
                    ? data.azurerm_subscription.subscriptions[replace(lower(coalesce(try(entry.scope, null), environment.subscription)), "sub:", "")].id
                    : (
                      startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload:")
                      ? local.workload_environment_subscription_id_by_name[replace(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload:", "")]
                      : (
                        startswith(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload-rg:")
                        ? local.workload_resource_group_scope_map[replace(lower(coalesce(try(entry.scope, null), environment.subscription)), "workload-rg:", "")]
                        : data.azurerm_subscription.subscriptions[coalesce(try(entry.scope, null), environment.subscription)].id
                      )
                    )
                  )
                )
              ),
              role_name
            )
          ]
        }
        if length(distinct(compact(flatten([
          try(entry.allowed_roles, [])
        ])))) > 0
      ]
    ],
    [
      for resource_group in local.workload_environment_resource_groups : [
        for entry_index, entry in try(resource_group.role_assignments.rbac_admin_roles, []) : {
          assignment_key           = format("%s-rbac-%d", resource_group.key, entry_index)
          workload_environment_key = resource_group.workload_environment_key
          scope_id = (
            coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id) == null
            ? azapi_resource.workload_resource_group[resource_group.key].id
            : (
              startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "/subscriptions/")
              ? coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)
              : (
                startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "sub:")
                ? data.azurerm_subscription.subscriptions[replace(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "sub:", "")].id
                : (
                  startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload:")
                  ? local.workload_environment_subscription_id_by_name[replace(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload:", "")]
                  : (
                    startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload-rg:")
                    ? local.workload_resource_group_scope_map[replace(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload-rg:", "")]
                    : data.azurerm_subscription.subscriptions[coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)].id
                  )
                )
              )
            )
          )
          principal_object_id = azuread_service_principal.workload[resource_group.workload_environment_key].object_id
          allowed_role_keys = [
            for role_name in distinct(compact(flatten([try(entry.allowed_roles, [])]))) :
            format(
              "%s|%s",
              tostring(
                coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id) == null
                ? azapi_resource.workload_resource_group[resource_group.key].id
                : (
                  startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "/subscriptions/")
                  ? coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)
                  : (
                    startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "sub:")
                    ? data.azurerm_subscription.subscriptions[replace(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "sub:", "")].id
                    : (
                      startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload:")
                      ? local.workload_environment_subscription_id_by_name[replace(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload:", "")]
                      : (
                        startswith(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload-rg:")
                        ? local.workload_resource_group_scope_map[replace(lower(coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)), "workload-rg:", "")]
                        : data.azurerm_subscription.subscriptions[coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)].id
                      )
                    )
                  )
                )
              ),
              role_name
            )
          ]
        }
        if length(distinct(compact(flatten([try(entry.allowed_roles, [])])))) > 0
      ]
    ]
  ))
}

data "azurerm_role_definition" "workload_rbac_allowed" {
  for_each = local.workload_rbac_allowed_role_map

  name = each.value.role_name
}

locals {
  workload_rbac_allowed_role_guids = {
    for key, definition in data.azurerm_role_definition.workload_rbac_allowed :
    key => element(split("/", definition.role_definition_id), length(split("/", definition.role_definition_id)) - 1)
  }
}

resource "azurerm_role_assignment" "workload_rbac_administrator" {
  for_each = { for assignment in local.workload_rbac_administrator_assignments : assignment.assignment_key => assignment }

  scope                = each.value.scope_id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azuread_service_principal.workload[each.value.workload_environment_key].object_id

  condition_version = "2.0"
  condition = trimspace(<<EOT
(
  (
    !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
  )
  OR
  (
    @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${join(", ", [for role_key in each.value.allowed_role_keys : local.workload_rbac_allowed_role_guids[role_key]])}}
  )
)
AND
(
  (
    !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
  )
  OR
  (
    @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${join(", ", [for role_key in each.value.allowed_role_keys : local.workload_rbac_allowed_role_guids[role_key]])}}
  )
)
EOT
  )
}
