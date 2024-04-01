// Assumption is that all workloads will have a GitHub repository
resource "github_repository" "workload" {
  for_each = { for each in var.workloads : each.name => each }

  name        = each.value.name
  description = each.value.github.description
  topics      = each.value.github.topics

  visibility = each.value.github.visibility

  has_downloads = each.value.github.has_downloads
  has_issues    = each.value.github.has_issues
  has_projects  = each.value.github.has_projects
  has_wiki      = each.value.github.has_wiki

  vulnerability_alerts = true

  allow_auto_merge       = true
  delete_branch_on_merge = true
}

locals {
  workload_environments = flatten([
    for environment_name, workload in var.workloads : [
      for environment in workload.environments : {
        key                          = format("%s-%s", workload.name, environment.name)
        workload_name                = workload.name
        environment_name             = environment.name
        connect_to_github            = environment.connect_to_github
        add_deploy_script_identity   = environment.add_deploy_script_identity
        configure_for_terraform      = environment.configure_for_terraform
        subscription                 = environment.subscription
        connect_to_devops            = environment.devops_project != null ? true : false
        devops_project               = environment.devops_project
        devops_create_variable_group = environment.devops_create_variable_group || (environment.devops_project != null && environment.add_deploy_script_identity) // If we're adding a deploy script identity, we need a variable group
        role_assignments             = environment.role_assignments
        directory_roles              = environment.directory_roles
      }
    ]
  ])
}

resource "random_id" "workload_id" {
  for_each = { for each in local.workload_environments : each.key => each }

  byte_length = 6
}

resource "azuread_application" "workload" {
  for_each = { for each in local.workload_environments : each.key => each }

  display_name = format("spn-%s-%s", lower(each.value.workload_name), lower(each.value.environment_name))

  owners = [
    data.azuread_client_config.current.object_id
  ]

  sign_in_audience = "AzureADMyOrg"
}

resource "azuread_service_principal" "workload" {
  for_each = { for each in local.workload_environments : each.key => each }

  client_id                    = azuread_application.workload[each.key].client_id
  app_role_assignment_required = false

  owners = [
    data.azuread_client_config.current.object_id
  ]
}

resource "github_repository_environment" "nuget" {
  for_each = { for each in var.workloads : each.name => each if each.github.add_nuget_environment }

  environment = "NuGet"
  repository  = github_repository.workload[each.value.name].name
}

resource "github_actions_environment_secret" "nuget_api_key" {
  for_each = { for each in var.workloads : each.name => each if each.github.add_nuget_environment }

  repository      = github_repository.workload[each.value.name].name
  environment     = github_repository_environment.nuget[each.key].environment
  secret_name     = "NUGET_API_KEY"
  plaintext_value = data.azurerm_key_vault_secret.nuget_token.value
}

resource "github_actions_secret" "sonar_token" {
  for_each = { for each in var.workloads : each.name => each if each.github.add_sonarcloud_secrets }

  repository      = github_repository.workload[each.value.name].name
  secret_name     = "SONAR_TOKEN"
  plaintext_value = data.azurerm_key_vault_secret.sonarcloud_token.value
}

resource "github_dependabot_secret" "sonar_token" {
  for_each = { for each in var.workloads : each.name => each if each.github.add_sonarcloud_secrets }

  repository      = github_repository.workload[each.value.name].name
  secret_name     = "SONAR_TOKEN"
  plaintext_value = data.azurerm_key_vault_secret.sonarcloud_token.value
}
