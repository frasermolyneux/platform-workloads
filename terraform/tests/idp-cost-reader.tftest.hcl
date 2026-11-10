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
      data.azuread_service_principal.idp_collector.client_id == "00000000-0000-0000-0000-000000000001" &&
      data.azuread_service_principal.idp_collector.object_id == "00000000-0000-0000-0000-000000000002"
    )
    error_message = "Resolve the collector from its authoritative IDP Production variable, not a copied principal ID or reverse remote state."
  }
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
