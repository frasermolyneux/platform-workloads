locals {
  gcp_environments = flatten([
    for workload in local.all_workloads : [
      for environment in try(workload.environments, []) : {
        key               = format("%s-%s", workload.name, environment.name)
        workload_name     = workload.name
        environment_name  = environment.name
        connect_to_github = try(environment.connect_to_github, false)
        gcp_project_id    = workload.gcp.project_id
        gcp_wif_provider  = workload.gcp.workload_identity_provider
        gcp_sa_email      = workload.gcp.service_account
      } if try(environment.gcp.enabled, false) && try(workload.gcp, null) != null
    ]
  ])
}

resource "github_actions_environment_variable" "gcp_project_id" {
  for_each = { for env in local.gcp_environments : env.key => env if env.connect_to_github }

  repository    = github_repository.workload[each.value.workload_name].name
  environment   = github_repository_environment.workload[each.key].environment
  variable_name = "GCP_PROJECT_ID"
  value         = each.value.gcp_project_id
}

resource "github_actions_environment_variable" "gcp_workload_identity_provider" {
  for_each = { for env in local.gcp_environments : env.key => env if env.connect_to_github }

  repository    = github_repository.workload[each.value.workload_name].name
  environment   = github_repository_environment.workload[each.key].environment
  variable_name = "GCP_WORKLOAD_IDENTITY_PROVIDER"
  value         = each.value.gcp_wif_provider
}

resource "github_actions_environment_variable" "gcp_service_account" {
  for_each = { for env in local.gcp_environments : env.key => env if env.connect_to_github }

  repository    = github_repository.workload[each.value.workload_name].name
  environment   = github_repository_environment.workload[each.key].environment
  variable_name = "GCP_SERVICE_ACCOUNT"
  value         = each.value.gcp_sa_email
}
