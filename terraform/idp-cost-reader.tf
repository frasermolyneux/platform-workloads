data "github_actions_environment_variables" "idp_collector" {
  full_name   = "frasermolyneux/platform-developer-portal"
  environment = "Production"

  lifecycle {
    postcondition {
      condition = try(
        length([for variable in self.variables : variable if variable.name == "IDP_COLLECTOR_CLIENT_ID"]) == 1 &&
        can(regex(
          "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
          one([for variable in self.variables : variable.value if variable.name == "IDP_COLLECTOR_CLIENT_ID"])
        )),
      false)
      error_message = "IDP Production must publish exactly one valid IDP_COLLECTOR_CLIENT_ID variable before collector cost access can be granted."
    }
  }
}

data "azuread_application" "idp_collector" {
  display_name = "MX.IO IDP CI collector (prd)"

  lifecycle {
    precondition {
      condition     = data.azuread_client_config.current.tenant_id == data.azurerm_client_config.current.tenant_id
      error_message = "Collector identity must be resolved in the Production deployment's Azure tenant."
    }

    postcondition {
      condition = (
        self.sign_in_audience == "AzureADMyOrg" &&
        self.client_id == one([
          for variable in data.github_actions_environment_variables.idp_collector.variables :
          variable.value if variable.name == "IDP_COLLECTOR_CLIENT_ID"
        ])
      )
      error_message = "IDP_COLLECTOR_CLIENT_ID must match the independently resolved, unique single-tenant IDP collector application; changing the GitHub variable must not retarget cost access."
    }
  }
}

data "azuread_service_principal" "idp_collector" {
  client_id = data.azuread_application.idp_collector.client_id
}

locals {
  idp_cost_reader_subscription_ids = toset([
    for policy in concat(values(local.subscription_cost_budget_policies), values(local.workload_cost_budget_policies)) :
    lower(policy.subscription_id)
  ])
}

resource "azurerm_role_assignment" "idp_cost_reader" {
  for_each             = local.idp_cost_reader_subscription_ids
  scope                = "/subscriptions/${each.value}"
  role_definition_name = "Cost Management Reader"
  principal_id         = data.azuread_service_principal.idp_collector.object_id
  principal_type       = "ServicePrincipal"

  depends_on = [terraform_data.cost_budget_contract]
}
