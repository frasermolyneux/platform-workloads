

resource "azurerm_user_assigned_identity" "workload_deploy_script" {
  for_each = { for each in local.workload_environments : each.key => each if each.add_deploy_script_identity }

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  name = format("spn-%s-%s-scripts", lower(each.value.workload_name), lower(each.value.environment_name))
}

resource "github_actions_environment_secret" "workload_deploy_script_identity" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_github && each.add_deploy_script_identity }

  repository      = github_repository.workload[each.value.workload_name].name
  environment     = github_repository_environment.workload[each.key].environment
  secret_name     = "AZURE_DEPLOY_SCRIPT_IDENTITY"
  plaintext_value = azurerm_user_assigned_identity.workload_deploy_script[each.key].id
}
