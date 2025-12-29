locals {
  workload_rbac_administrator_map = {
    for environment in local.workload_environments :
    environment.key => [
      for entry in try(environment.role_assignments.rbac_admin_roles, []) : {
        workload_name          = environment.workload_name
        environment_name       = environment.environment_name
        service_principal_name = format("spn-%s-%s", lower(environment.workload_name), lower(environment.environment_name))
        scope_value            = coalesce(try(entry.scope, null), environment.subscription)
        scope_resolved = (
          scope_value == null
          ? data.azurerm_subscription.subscriptions[environment.subscription].id
          : (
            startswith(lower(scope_value), "/subscriptions/")
            ? scope_value
            : (
              startswith(lower(scope_value), "sub:")
              ? data.azurerm_subscription.subscriptions[replace(lower(scope_value), "sub:", "")].id
              : (
                startswith(lower(scope_value), "workload:")
                ? local.workload_environment_subscription_id_by_name[replace(lower(scope_value), "workload:", "")]
                : (
                  startswith(lower(scope_value), "workload-rg:")
                  ? local.workload_resource_group_scope_map[replace(lower(scope_value), "workload-rg:", "")]
                  : data.azurerm_subscription.subscriptions[scope_value].id
                )
              )
            )
          )
        )
        scope_name      = scope_resolved
        scope_id        = scope_resolved
        subscription_id = try(data.azurerm_subscription.subscriptions[scope_value].subscription_id, null)
        allowed_roles = distinct(compact(flatten([
          try(entry.allowed_roles, [])
        ])))
      }
      if length(distinct(compact(flatten([
        try(entry.allowed_roles, [])
      ])))) > 0
    ]
    if length([
      for entry in try(environment.role_assignments.rbac_admin_roles, []) : 1
      if length(distinct(compact(flatten([try(entry.allowed_roles, [])])))) > 0
    ]) > 0
  }

  // Environment-scoped RBAC roles (all values known at plan time)
  workload_rbac_allowed_role_map_env = {
    for request in distinct(flatten([
      for environment in local.workload_environments : [
        for entry in try(environment.role_assignments.rbac_admin_roles, []) : [
          for role_name in distinct(compact(flatten([
            try(entry.allowed_roles, [])
            ]))) : {
            scope_value = coalesce(try(entry.scope, null), environment.subscription)
            scope_resolved = (
              scope_value == null
              ? data.azurerm_subscription.subscriptions[environment.subscription].id
              : (
                startswith(lower(scope_value), "/subscriptions/")
                ? scope_value
                : (
                  startswith(lower(scope_value), "sub:")
                  ? data.azurerm_subscription.subscriptions[replace(lower(scope_value), "sub:", "")].id
                  : (
                    startswith(lower(scope_value), "workload:")
                    ? local.workload_environment_subscription_id_by_name[replace(lower(scope_value), "workload:", "")]
                    : (
                      startswith(lower(scope_value), "workload-rg:")
                      ? local.workload_resource_group_scope_map[replace(lower(scope_value), "workload-rg:", "")]
                      : data.azurerm_subscription.subscriptions[scope_value].id
                    )
                  )
                )
              )
            )
            key        = format("%s|%s", scope_resolved, role_name)
            scope_name = scope_resolved
            role_name  = role_name
          }
        ]
      ]
    ])) :
    request.key => {
      scope_name = request.scope_name
      role_name  = request.role_name
    }
  }

  // Resource-group-scoped RBAC roles (scope IDs resolve after apply, but keys are fully known at plan time)
  workload_rbac_allowed_role_map_rg = {
    for request in flatten([
      for resource_group in local.workload_environment_resource_groups : [
        for entry in try(resource_group.role_assignments.rbac_admin_roles, []) : [
          for role_name in distinct(compact(flatten([try(entry.allowed_roles, [])]))) : {
            scope_value = coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)
            scope_resolved = (
              scope_value == null
              ? azapi_resource.workload_resource_group[resource_group.key].id
              : (
                startswith(lower(scope_value), "/subscriptions/")
                ? scope_value
                : (
                  startswith(lower(scope_value), "sub:")
                  ? data.azurerm_subscription.subscriptions[replace(lower(scope_value), "sub:", "")].id
                  : (
                    startswith(lower(scope_value), "workload:")
                    ? local.workload_environment_subscription_id_by_name[replace(lower(scope_value), "workload:", "")]
                    : (
                      startswith(lower(scope_value), "workload-rg:")
                      ? local.workload_resource_group_scope_map[replace(lower(scope_value), "workload-rg:", "")]
                      : data.azurerm_subscription.subscriptions[scope_value].id
                    )
                  )
                )
              )
            )
            key        = format("%s|%s", scope_resolved, role_name)
            scope_name = scope_resolved
            role_name  = role_name
          }
        ]
      ]
    ]) :
    request.key => {
      scope_name = request.scope_name
      role_name  = request.role_name
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
          scope_value              = coalesce(try(entry.scope, null), environment.subscription)
          scope_id = (
            scope_value == null
            ? data.azurerm_subscription.subscriptions[environment.subscription].id
            : (
              startswith(lower(scope_value), "/subscriptions/")
              ? scope_value
              : (
                startswith(lower(scope_value), "sub:")
                ? data.azurerm_subscription.subscriptions[replace(lower(scope_value), "sub:", "")].id
                : (
                  startswith(lower(scope_value), "workload:")
                  ? local.workload_environment_subscription_id_by_name[replace(lower(scope_value), "workload:", "")]
                  : (
                    startswith(lower(scope_value), "workload-rg:")
                    ? local.workload_resource_group_scope_map[replace(lower(scope_value), "workload-rg:", "")]
                    : data.azurerm_subscription.subscriptions[scope_value].id
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
            format("%s|%s", scope_id, role_name)
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
          scope_value              = coalesce(entry.scope, azapi_resource.workload_resource_group[resource_group.key].id)
          scope_id = (
            scope_value == null
            ? azapi_resource.workload_resource_group[resource_group.key].id
            : (
              startswith(lower(scope_value), "/subscriptions/")
              ? scope_value
              : (
                startswith(lower(scope_value), "sub:")
                ? data.azurerm_subscription.subscriptions[replace(lower(scope_value), "sub:", "")].id
                : (
                  startswith(lower(scope_value), "workload:")
                  ? local.workload_environment_subscription_id_by_name[replace(lower(scope_value), "workload:", "")]
                  : (
                    startswith(lower(scope_value), "workload-rg:")
                    ? local.workload_resource_group_scope_map[replace(lower(scope_value), "workload-rg:", "")]
                    : data.azurerm_subscription.subscriptions[scope_value].id
                  )
                )
              )
            )
          )
          principal_object_id = azuread_service_principal.workload[resource_group.workload_environment_key].object_id
          allowed_role_keys = [
            for role_name in distinct(compact(flatten([try(entry.allowed_roles, [])]))) :
            format("%s|%s", scope_id, role_name)
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
