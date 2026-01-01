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
        key                          = format("%s-%s", workload.name, environment.name)
        workload_name                = workload.name
        environment_name             = environment.name
        environment_tag              = lookup(var.environment_map, environment.name, lower(environment.name))
        connect_to_github            = try(environment.connect_to_github, false)
        add_deploy_script_identity   = try(environment.add_deploy_script_identity, false)
        configure_for_terraform      = try(environment.configure_for_terraform, false)
        subscription                 = environment.subscription
        connect_to_devops            = try(environment.devops_project, null) != null
        devops_project               = try(environment.devops_project, null)
        devops_create_variable_group = try(environment.devops_create_variable_group, false) || (try(environment.devops_project, null) != null && try(environment.add_deploy_script_identity, false))
        role_assignments = {
          assigned_roles = [
            for assignment in concat(
              try(environment.role_assignments.assigned_roles, []),
              length([
                for existing in try(environment.role_assignments.assigned_roles, []) : 1
                if coalesce(try(existing.scope, null), environment.subscription) == environment.subscription
                ]) == 0 ? [
                {
                  scope = environment.subscription
                  roles = ["Reader"]
                }
              ] : []
              ) : merge(
              {
                scope = coalesce(try(assignment.scope, null), environment.subscription)
                roles = distinct(try(assignment.roles, []))
              },
              coalesce(try(assignment.scope, null), environment.subscription) == environment.subscription
              ? { roles = distinct(concat(try(assignment.roles, []), ["Reader"])) }
              : {}
            )
          ]
          rbac_admin_roles = [
            for assignment in try(environment.role_assignments.rbac_admin_roles, []) : {
              scope         = coalesce(try(assignment.scope, null), environment.subscription)
              allowed_roles = distinct(try(assignment.allowed_roles, []))
            }
            if length(distinct(compact(flatten([try(assignment.allowed_roles, [])])))) > 0
          ]
        }
        directory_roles = try(environment.directory_roles, [])
        administrative_unit_roles = (
          try(environment.administrative_unit_roles, null) != null
          ? [
            {
              administrative_unit_key = try(environment.administrative_unit_roles.administrative_unit, null)
              roles                   = distinct(try(environment.administrative_unit_roles.roles, []))
            }
          ]
          : []
        )
        administrative_unit_keys = (
          try(environment.administrative_unit_roles, null) != null && try(environment.administrative_unit_roles.administrative_unit, null) != null
          ? [environment.administrative_unit_roles.administrative_unit]
          : []
        )
        requires_terraform_state_access = try(environment.requires_terraform_state_access, [])
        locations                       = [for location in try(coalesce(environment.locations, ["uksouth"]), ["uksouth"]) : lower(location)]
        resource_groups                 = try(environment.resource_groups, null)
      }
    ]
  ])
}

locals {
  // Fast lookups for scope resolution and cross-environment references
  workload_environments_map = { for environment in local.workload_environments : environment.key => environment }

  workload_environment_lookup_by_name = {
    for environment in local.workload_environments :
    lower(format("%s/%s", environment.workload_name, environment.environment_name)) => environment
  }

  workload_environment_subscription_id_map = {
    for environment in local.workload_environments : environment.key => data.azurerm_subscription.subscriptions[environment.subscription].id
  }

  workload_environment_subscription_id_by_name = {
    for environment in local.workload_environments :
    lower(format("%s/%s", environment.workload_name, environment.environment_name)) => data.azurerm_subscription.subscriptions[environment.subscription].id
  }
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
