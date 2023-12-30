resource "azuread_application_password" "legacy_workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_github && each.add_legacy_secret }

  display_name   = format("github-%s-%s", lower(each.value.workload_name), lower(each.value.environment_name))
  application_id = azuread_application.workload[each.key].id

  rotate_when_changed = {
    rotation = time_rotating.rotate.id
  }
}

resource "github_actions_environment_secret" "legacy_secret" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_github && each.add_legacy_secret }

  repository      = github_repository.workload[each.value.workload_name].name
  environment     = github_repository_environment.workload[each.key].environment
  secret_name     = "AZURE_LEGACY_SECRET"
  plaintext_value = azuread_application_password.legacy_workload[each.key].value
}
