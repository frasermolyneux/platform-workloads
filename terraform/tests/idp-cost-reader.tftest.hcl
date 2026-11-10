variable "subscriptions" {
  type = any
}

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000004"
    }
  }
}

mock_provider "github" {
  mock_data "github_actions_environment_variables" {
    defaults = {
      variables = [{
        name  = "IDP_COLLECTOR_CLIENT_ID"
        value = "00000000-0000-0000-0000-000000000001"
      }]
    }
  }
}

mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000004"
    }
  }

  mock_data "azuread_application" {
    defaults = {
      client_id        = "00000000-0000-0000-0000-000000000001"
      sign_in_audience = "AzureADMyOrg"
    }
  }

  mock_data "azuread_service_principal" {
    defaults = {
      object_id = "00000000-0000-0000-0000-000000000002"
    }
  }
}

run "resolve_authoritative_collector" {
  command = plan

  plan_options {
    target = [data.azuread_service_principal.idp_collector]
  }

  assert {
    condition = (
      data.github_actions_environment_variables.idp_collector.full_name == "frasermolyneux/platform-developer-portal" &&
      data.github_actions_environment_variables.idp_collector.environment == "Production" &&
      data.azuread_application.idp_collector.display_name == "MX.IO IDP host collector (prd)" &&
      data.azuread_application.idp_collector.client_id == "00000000-0000-0000-0000-000000000001" &&
      data.azuread_service_principal.idp_collector.client_id == "00000000-0000-0000-0000-000000000001" &&
      data.azuread_service_principal.idp_collector.object_id == "00000000-0000-0000-0000-000000000002"
    )
    error_message = "Resolve the collector from its authoritative IDP Production variable, not a copied principal ID or reverse remote state."
  }
}

run "grant_exact_policy_subscription_access" {
  command = plan

  plan_options {
    target = [azurerm_role_assignment.idp_cost_reader]
  }

  assert {
    condition = (
      toset(keys(azurerm_role_assignment.idp_cost_reader)) == toset([
        for policy in concat(values(output.cost_budget_policies.subscriptions), values(output.cost_budget_policies.workload_environments)) :
        lower(policy.subscription_id)
      ]) &&
      alltrue([
        for subscription_id, assignment in azurerm_role_assignment.idp_cost_reader :
        assignment.scope == "/subscriptions/${subscription_id}" &&
        assignment.role_definition_name == "Cost Management Reader" &&
        assignment.principal_id == data.azuread_service_principal.idp_collector.object_id &&
        assignment.principal_type == "ServicePrincipal"
      ])
    )
    error_message = "Grant only the selected built-in role to the authoritative collector at each distinct policy subscription, never tenant or management-group scope."
  }
}

run "deduplicate_subscription_aliases" {
  command = plan

  variables {
    subscriptions = merge(var.subscriptions, {
      collector_alias = merge(var.subscriptions["sub-platform-shared"], {
        name        = "collector-alias-test"
        cost_budget = null
      })
    })
  }

  plan_options {
    target = [azurerm_role_assignment.idp_cost_reader]
  }

  assert {
    condition = length(azurerm_role_assignment.idp_cost_reader) == length(toset([
      for policy in concat(values(output.cost_budget_policies.subscriptions), values(output.cost_budget_policies.workload_environments)) :
      lower(policy.subscription_id)
    ]))
    error_message = "Aliases for the same subscription must not create duplicate role assignments."
  }
}

run "include_new_policy_subscription" {
  command = plan

  variables {
    subscriptions = merge(var.subscriptions, {
      collector_new = {
        subscription_id = "00000000-0000-0000-0000-000000000003"
        name            = "collector-new-test"
        environment     = "Production"
        monthly_budget  = 5
      }
    })
  }

  plan_options {
    target = [azurerm_role_assignment.idp_cost_reader]
  }

  assert {
    condition     = azurerm_role_assignment.idp_cost_reader["00000000-0000-0000-0000-000000000003"].scope == "/subscriptions/00000000-0000-0000-0000-000000000003"
    error_message = "A newly configured policy subscription must receive collector access without a second scope catalog."
  }
}

run "include_workload_only_policy_subscription" {
  command = plan

  variables {
    subscriptions = merge(var.subscriptions, {
      sub-platform-shared = merge(var.subscriptions["sub-platform-shared"], {
        monthly_budget = null
        cost_budget    = null
      })
    })
  }

  plan_options {
    target = [azurerm_role_assignment.idp_cost_reader]
  }

  assert {
    condition = (
      !contains(keys(output.cost_budget_policies.subscriptions), "sub-platform-shared") &&
      azurerm_role_assignment.idp_cost_reader[lower(var.subscriptions["sub-platform-shared"].subscription_id)].scope == "/subscriptions/${lower(var.subscriptions["sub-platform-shared"].subscription_id)}"
    )
    error_message = "Workload policies must retain collector access even when their subscription has no independent budget."
  }
}

run "exclude_subscription_without_policy" {
  command = plan

  variables {
    subscriptions = merge(var.subscriptions, {
      collector_unbudgeted = {
        subscription_id = "00000000-0000-0000-0000-000000000003"
        name            = "collector-unbudgeted-test"
        environment     = "Production"
      }
    })
  }

  plan_options {
    target = [azurerm_role_assignment.idp_cost_reader]
  }

  assert {
    condition     = !contains(keys(azurerm_role_assignment.idp_cost_reader), "00000000-0000-0000-0000-000000000003")
    error_message = "An unrelated subscription with no budget policy must not receive collector access."
  }
}

run "reject_substituted_github_principal" {
  command = plan

  override_data {
    target = data.github_actions_environment_variables.idp_collector
    values = {
      variables = [{ name = "IDP_COLLECTOR_CLIENT_ID", value = "00000000-0000-0000-0000-000000000003" }]
    }
  }

  plan_options {
    target = [azurerm_role_assignment.idp_cost_reader]
  }

  expect_failures = [data.azuread_application.idp_collector]
}

run "reject_replaced_directory_application" {
  command = plan

  override_data {
    target = data.azuread_application.idp_collector
    values = {
      client_id        = "00000000-0000-0000-0000-000000000003"
      sign_in_audience = "AzureADMyOrg"
    }
  }

  plan_options {
    target = [azurerm_role_assignment.idp_cost_reader]
  }

  expect_failures = [data.azuread_application.idp_collector]
}

run "reject_different_directory_tenant" {
  command = plan

  override_data {
    target = data.azuread_client_config.current
    values = { tenant_id = "00000000-0000-0000-0000-000000000005" }
  }

  plan_options {
    target = [azurerm_role_assignment.idp_cost_reader]
  }

  expect_failures = [data.azuread_application.idp_collector]
}

run "reject_multitenant_collector_application" {
  command = plan

  override_data {
    target = data.azuread_application.idp_collector
    values = {
      client_id        = "00000000-0000-0000-0000-000000000001"
      sign_in_audience = "AzureADMultipleOrgs"
    }
  }

  plan_options {
    target = [azurerm_role_assignment.idp_cost_reader]
  }

  expect_failures = [data.azuread_application.idp_collector]
}

run "reject_missing_collector_variable" {
  command = plan

  override_data {
    target = data.github_actions_environment_variables.idp_collector
    values = { variables = [] }
  }

  plan_options {
    target = [data.github_actions_environment_variables.idp_collector]
  }

  expect_failures = [data.github_actions_environment_variables.idp_collector]
}

run "reject_ambiguous_collector_variable" {
  command = plan

  override_data {
    target = data.github_actions_environment_variables.idp_collector
    values = {
      variables = [
        { name = "IDP_COLLECTOR_CLIENT_ID", value = "00000000-0000-0000-0000-000000000001" },
        { name = "IDP_COLLECTOR_CLIENT_ID", value = "00000000-0000-0000-0000-000000000003" },
      ]
    }
  }

  plan_options {
    target = [data.github_actions_environment_variables.idp_collector]
  }

  expect_failures = [data.github_actions_environment_variables.idp_collector]
}

run "reject_invalid_collector_client_id" {
  command = plan

  override_data {
    target = data.github_actions_environment_variables.idp_collector
    values = {
      variables = [{ name = "IDP_COLLECTOR_CLIENT_ID", value = "not-a-client-id" }]
    }
  }

  plan_options {
    target = [data.github_actions_environment_variables.idp_collector]
  }

  expect_failures = [data.github_actions_environment_variables.idp_collector]
}
