resource "github_actions_secret" "github_app_pem" {
  for_each = { for workload in local.all_workloads : workload.name => workload if try(workload.github.github_app.enabled, false) }

  repository      = github_repository.workload[each.value.name].name
  secret_name     = "GH_APP_PEM"
  plaintext_value = data.azurerm_key_vault_secret.github_app_pem.value
}

resource "github_actions_variable" "github_app_id" {
  for_each = { for workload in local.all_workloads : workload.name => workload if try(workload.github.github_app.enabled, false) }

  repository    = github_repository.workload[each.value.name].name
  variable_name = "GH_APP_ID"
  value         = each.value.github.github_app.app_id
}

resource "github_actions_variable" "github_app_installation_id" {
  for_each = { for workload in local.all_workloads : workload.name => workload if try(workload.github.github_app.enabled, false) }

  repository    = github_repository.workload[each.value.name].name
  variable_name = "GH_APP_INSTALLATION_ID"
  value         = each.value.github.github_app.installation_id
}
