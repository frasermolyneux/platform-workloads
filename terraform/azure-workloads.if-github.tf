moved {
  from = azuread_application_federated_identity_credential.workload
  to   = azuread_application_federated_identity_credential.github_workload
}

resource "azuread_application_federated_identity_credential" "github_workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_github }

  application_id = azuread_application.workload[each.key].id
  display_name   = format("github-%s-%s", lower(each.value.workload_name), lower(each.value.environment_name))
  description    = "GitHub Actions"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = format("repo:frasermolyneux/%s:environment:%s", lower(each.value.workload_name), each.value.environment_name)
}

resource "github_repository_environment" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_github }

  environment = each.value.environment_name
  repository  = github_repository.workload[each.value.workload_name].name
}

resource "github_actions_environment_variable" "client_id" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_github }

  repository    = github_repository.workload[each.value.workload_name].name
  environment   = github_repository_environment.workload[each.key].environment
  variable_name = "AZURE_CLIENT_ID"
  value         = azuread_application.workload[each.key].client_id
}

resource "github_actions_environment_variable" "subscription_id" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_github }

  repository    = github_repository.workload[each.value.workload_name].name
  environment   = github_repository_environment.workload[each.key].environment
  variable_name = "AZURE_SUBSCRIPTION_ID"
  value         = var.subscriptions[each.value.subscription].subscription_id
}

resource "github_actions_environment_variable" "tenant_id" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_github }

  repository    = github_repository.workload[each.value.workload_name].name
  environment   = github_repository_environment.workload[each.key].environment
  variable_name = "AZURE_TENANT_ID"
  value         = "e56a6947-bb9a-4a6e-846a-1f118d1c3a14"
}
