locals {
  workload_role_assignments = distinct(flatten([
    for workload_environment in local.workload_environments : [
      for role_assignment in workload_environment.role_assignments.assigned_roles : [
        for role_definition in role_assignment.roles : {
          role_assignment_key        = format("%s-%s-%s", workload_environment.key, role_definition, role_assignment.scope)
          workload_environment_key   = workload_environment.key
          add_deploy_script_identity = workload_environment.add_deploy_script_identity
          scope_value                = coalesce(role_assignment.scope, workload_environment.subscription)
          resolved_scope = (
            role_assignment.scope == null
            ? data.azurerm_subscription.subscriptions[workload_environment.subscription].id
            : (
              startswith(lower(role_assignment.scope), "/subscriptions/")
              ? role_assignment.scope
              : (
                startswith(lower(role_assignment.scope), "sub:")
                ? data.azurerm_subscription.subscriptions[replace(lower(role_assignment.scope), "sub:", "")].id
                : (
                  startswith(lower(role_assignment.scope), "workload:")
                  ? local.workload_environment_subscription_id_by_name[replace(lower(role_assignment.scope), "workload:", "")]
                  : (
                    startswith(lower(role_assignment.scope), "workload-rg:")
                    ? local.workload_resource_group_scope_map[replace(lower(role_assignment.scope), "workload-rg:", "")]
                    : data.azurerm_subscription.subscriptions[role_assignment.scope].id
                  )
                )
              )
            )
          )
          role_definition_name = role_definition
        }
      ]
    ]
  ]))

  plan_role_subscriptions = distinct(concat(
    [for workload_environment in local.workload_environments : workload_environment.subscription],
    flatten([for workload_environment in local.workload_environments : workload_environment.plan_subscriptions if length(workload_environment.plan_subscriptions) > 0])
  ))

  plan_role_assignments = flatten([
    for workload_environment in local.workload_environments : [
      for subscription in workload_environment.plan_subscriptions : {
        key          = format("%s-%s", workload_environment.key, subscription)
        env_key      = workload_environment.key
        subscription = subscription
      }
    ]
  ])
}

resource "random_uuid" "plan_read_only" {
  for_each = toset(local.plan_role_subscriptions)
}

resource "azurerm_role_definition" "plan_read_only" {
  for_each = toset(local.plan_role_subscriptions)

  name        = random_uuid.plan_read_only[each.key].result
  scope       = data.azurerm_subscription.subscriptions[each.key].id
  description = "Read-only permissions for Terraform plan identities, including App Service config list actions."

  permissions {
    actions = [
      "Microsoft.Web/sites/read",
      "Microsoft.Web/sites/config/read",
      "Microsoft.Web/sites/config/list/action",
      "Microsoft.Web/sites/functions/read",
      "Microsoft.Web/sites/slots/read",
      "Microsoft.Web/sites/slots/config/read",
      "Microsoft.Web/sites/slots/config/list/action",
      "Microsoft.Web/sites/slots/functions/read",
      "Microsoft.Web/serverfarms/read",
      "Microsoft.KeyVault/vaults/read",
      "Microsoft.KeyVault/vaults/secrets/read",
      "Microsoft.Storage/storageAccounts/listKeys/action"
    ]
    data_actions = [
      "Microsoft.KeyVault/vaults/secrets/getSecret/action"
    ]
    not_actions = []
  }

  assignable_scopes = [data.azurerm_subscription.subscriptions[each.key].id]
}

resource "azurerm_role_assignment" "workload" {
  for_each = { for each in local.workload_role_assignments : each.role_assignment_key => each }

  scope                = each.value.resolved_scope
  role_definition_name = each.value.role_definition_name
  principal_id         = azuread_service_principal.workload[each.value.workload_environment_key].object_id
}

resource "azurerm_role_assignment" "workload_deploy_script" {
  for_each = { for each in local.workload_role_assignments : each.role_assignment_key => each if each.add_deploy_script_identity }

  scope                = each.value.resolved_scope
  role_definition_name = each.value.role_definition_name
  principal_id         = azurerm_user_assigned_identity.workload_deploy_script[each.value.workload_environment_key].principal_id
}

# Plan-only identity gets Reader on the subscription so it can perform Terraform plans without write permissions.
resource "azurerm_role_assignment" "workload_plan_reader" {
  for_each = { for each in local.plan_role_assignments : each.key => each }

  scope                = data.azurerm_subscription.subscriptions[each.value.subscription].id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.workload_plan[each.value.env_key].object_id
}

resource "azurerm_role_assignment" "workload_plan_read_only" {
  for_each = { for each in local.plan_role_assignments : each.key => each }

  scope              = data.azurerm_subscription.subscriptions[each.value.subscription].id
  role_definition_id = azurerm_role_definition.plan_read_only[each.value.subscription].role_definition_resource_id
  principal_id       = azuread_service_principal.workload_plan[each.value.env_key].object_id
}
