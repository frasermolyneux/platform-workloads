

resource "azurerm_user_assigned_identity" "workload_deploy_script" {
  for_each = { for each in local.workload_environments : each.key => each if each.add_deploy_script_identity }

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  name = format("spn-%s-%s-scripts", lower(each.value.workload_name), lower(each.value.environment_name))
}

resource "azurerm_role_assignment" "workload_managed_identity_operator" {
  for_each = { for each in local.workload_environments : each.key => each if each.add_deploy_script_identity }

  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azuread_service_principal.workload[each.key].object_id
}

resource "github_actions_environment_secret" "workload_deploy_script_identity" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_github && each.add_deploy_script_identity }

  repository      = github_repository.workload[each.value.workload_name].name
  environment     = github_repository_environment.workload[each.key].environment
  secret_name     = "AZURE_DEPLOY_SCRIPT_IDENTITY"
  plaintext_value = azurerm_user_assigned_identity.workload_deploy_script[each.key].id
}

// If we are connecting to Azure DevOps, add the secret to the key vault
//resource "azurerm_key_vault_secret" "workload_deploy_script_identity_secret" {
//  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops && each.add_deploy_script_identity }
//
//  name         = "azure-deploy-script-identity"
//  value        = azurerm_user_assigned_identity.workload_deploy_script[each.key].id
//  key_vault_id = azurerm_key_vault.workload[each.key].id
//
//  depends_on = [
//    azurerm_role_assignment.deploy_principal_workload_key_vault_secrets_officer
//  ]
//}

// If this is a development environment, also add the secrets as a dependabot secret
resource "github_dependabot_secret" "workload_deploy_script_identity" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_github && each.add_deploy_script_identity && each.environment_name == "Development" }

  repository      = github_repository.workload[each.value.workload_name].name
  secret_name     = "AZURE_DEPLOY_SCRIPT_IDENTITY"
  plaintext_value = azurerm_user_assigned_identity.workload_deploy_script[each.key].id
}
