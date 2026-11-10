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

data "azuread_service_principal" "idp_collector" {
  client_id = one([
    for variable in data.github_actions_environment_variables.idp_collector.variables :
    variable.value if variable.name == "IDP_COLLECTOR_CLIENT_ID"
  ])
}
