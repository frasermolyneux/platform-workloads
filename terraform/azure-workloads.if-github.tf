moved {
  from = azuread_application_federated_identity_credential.workload
  to   = azuread_application_federated_identity_credential.github_workload
}

// GitHub's OIDC `sub` claim format depends on when the repository was created:
// - Repositories created before GitHub's immutable-subject rollout (2026-07-15) keep the
//   legacy "repo:{owner}/{repo}:environment:{env}" format unless they explicitly opt in.
// - Repositories created after that date default to the immutable
//   "repo:{owner}@{owner_id}/{repo}@{repo_id}:environment:{env}" format, and this cannot be
//   reliably forced back to the legacy format via the repo-level OIDC customization API
//   (verified empirically against api.github.com/repos/frasermolyneux/trip-side-kick/actions/oidc/customization/sub -
//   `use_immutable_subject: false` did not change the effective subject prefix).
// We therefore register BOTH subject formats as federated credentials so a workload's
// service principal authenticates correctly regardless of which subject GitHub presents.
// frasermolyneux is a personal user account, not a GitHub organization, so the
// `github_organization` data source (which reads /orgs/{name}) 404s here - use `github_user`.
data "github_user" "current" {
  username = "frasermolyneux"
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

resource "azuread_application_federated_identity_credential" "github_workload_immutable" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_github }

  application_id = azuread_application.workload[each.key].id
  display_name   = format("github-%s-%s-immutable", lower(each.value.workload_name), lower(each.value.environment_name))
  description    = "GitHub Actions (immutable subject claim - see comment on github_workload)"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject = format(
    "repo:frasermolyneux@%s/%s@%s:environment:%s",
    data.github_user.current.id,
    github_repository.workload[each.value.workload_name].name,
    github_repository.workload[each.value.workload_name].repo_id,
    each.value.environment_name
  )
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
