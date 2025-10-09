// Assumption is that all workloads will have a GitHub repository
resource "github_repository" "workload" {
  for_each = { for workload in local.all_workloads : workload.name => workload }

  name        = each.value.name
  description = each.value.github.description
  topics      = each.value.github.topics

  visibility = each.value.github.visibility

  has_downloads = try(each.value.github.has_downloads, false)
  has_issues    = try(each.value.github.has_issues, false)
  has_projects  = try(each.value.github.has_projects, false)
  has_wiki      = try(each.value.github.has_wiki, false)

  vulnerability_alerts = true

  allow_auto_merge       = true
  delete_branch_on_merge = true
}

locals {
  workload_environments = flatten([
    for workload in local.all_workloads : [
      for environment in try(workload.environments, []) : {
        key                             = format("%s-%s", workload.name, environment.name)
        workload_name                   = workload.name
        create_dev_center_project       = try(workload.create_dev_center_project, false)
        environment_name                = environment.name
        environment_tag                 = lookup(var.environment_map, environment.name, lower(environment.name))
        connect_to_github               = try(environment.connect_to_github, false)
        add_deploy_script_identity      = try(environment.add_deploy_script_identity, false)
        configure_for_terraform         = try(environment.configure_for_terraform, false)
        subscription                    = environment.subscription
        connect_to_devops               = try(environment.devops_project, null) != null
        devops_project                  = try(environment.devops_project, null)
        devops_create_variable_group    = try(environment.devops_create_variable_group, false) || (try(environment.devops_project, null) != null && try(environment.add_deploy_script_identity, false))
        role_assignments                = try(environment.role_assignments, [])
        rbac_administrator              = try(environment.rbac_administrator, [])
        directory_roles                 = try(environment.directory_roles, [])
        requires_terraform_state_access = try(environment.requires_terraform_state_access, [])
        locations                       = [for location in try(coalesce(environment.locations, ["uksouth"]), ["uksouth"]) : lower(location)]
        resource_groups                 = try(environment.resource_groups, null)
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
  for_each = { for workload in local.all_workloads : workload.name => workload if try(workload.github.add_nuget_environment, false) }

  environment = "NuGet"
  repository  = github_repository.workload[each.value.name].name
}

resource "github_actions_environment_secret" "nuget_api_key" {
  for_each = { for workload in local.all_workloads : workload.name => workload if try(workload.github.add_nuget_environment, false) }

  repository      = github_repository.workload[each.value.name].name
  environment     = github_repository_environment.nuget[each.key].environment
  secret_name     = "NUGET_API_KEY"
  plaintext_value = data.azurerm_key_vault_secret.nuget_token.value
}

resource "github_actions_secret" "sonar_token" {
  for_each = { for workload in local.all_workloads : workload.name => workload if try(workload.github.add_sonarcloud_secrets, false) }

  repository      = github_repository.workload[each.value.name].name
  secret_name     = "SONAR_TOKEN"
  plaintext_value = data.azurerm_key_vault_secret.sonarcloud_token.value
}

resource "github_dependabot_secret" "sonar_token" {
  for_each = { for workload in local.all_workloads : workload.name => workload if try(workload.github.add_sonarcloud_secrets, false) }

  repository      = github_repository.workload[each.value.name].name
  secret_name     = "SONAR_TOKEN"
  plaintext_value = data.azurerm_key_vault_secret.sonarcloud_token.value
}
