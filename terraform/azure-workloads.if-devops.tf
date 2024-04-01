resource "azuread_application_password" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  display_name   = format("azdo-%s-%s", lower(each.value.workload_name), lower(each.value.environment_name))
  application_id = azuread_application.workload[each.key].id

  rotate_when_changed = {
    rotation = time_rotating.rotate.id
  }
}

resource "azuredevops_environment" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  project_id = azuredevops_project.project[each.value.devops_project].id
  name       = each.key
}

resource "azuredevops_pipeline_authorization" "workload_environment" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  project_id  = azuredevops_project.project[each.value.devops_project].id
  resource_id = azuredevops_environment.workload[each.key].id

  type = "environment"
}

resource "azuredevops_serviceendpoint_azurerm" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  project_id            = azuredevops_project.project[each.value.devops_project].id
  service_endpoint_name = azuread_application.workload[each.key].display_name
  description           = "Managed By platform-workloads"

  credentials {
    serviceprincipalid  = azuread_service_principal.workload[each.key].application_id
    serviceprincipalkey = azuread_application_password.workload[each.key].value
  }

  azurerm_spn_tenantid      = "e56a6947-bb9a-4a6e-846a-1f118d1c3a14"
  azurerm_subscription_id   = var.subscriptions[each.value.subscription].subscription_id
  azurerm_subscription_name = var.subscriptions[each.value.subscription].name
}

resource "azuredevops_pipeline_authorization" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  project_id  = azuredevops_project.project[each.value.devops_project].id
  resource_id = azuredevops_serviceendpoint_azurerm.workload[each.key].id

  type = "endpoint"
}

resource "azurerm_resource_group" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.devops_create_variable_group }

  name     = format("rg-ado-%s-%s-%s-%s", each.value.workload_name, var.environment_map[each.value.environment_name], var.location, var.instance)
  location = var.location

  tags = merge(var.tags, { Workload = each.value.workload_name, Environment = each.value.environment_name })
}

resource "azurerm_key_vault" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.devops_create_variable_group }

  name                = format("kv-%s-%s-%s-%s", each.value.workload_name, var.environment_map[each.value.environment_name], var.location, var.instance)
  location            = var.location
  resource_group_name = azurerm_resource_group.workload[each.key].name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  tags = merge(var.tags, { Workload = each.value.workload_name, Environment = each.value.environment_name })

  soft_delete_retention_days = 90
  purge_protection_enabled   = true
  enable_rbac_authorization  = true

  sku_name = "standard"

  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow"
  }
}

resource "azurerm_role_assignment" "workload_key_vault_secrets_officer" {
  for_each = { for each in local.workload_environments : each.key => each if each.devops_create_variable_group }

  scope                = azurerm_key_vault.workload[each.key].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azuread_service_principal.workload[each.key].object_id
}

resource "azurerm_role_assignment" "deploy_principal_workload_key_vault_secrets_officer" {
  for_each = { for each in local.workload_environments : each.key => each if each.devops_create_variable_group }

  scope                = azurerm_key_vault.workload[each.key].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azuredevops_variable_group" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.devops_create_variable_group }

  project_id  = azuredevops_project.project[each.value.devops_project].id
  name        = each.key
  description = "Variable group for ${each.key}"

  allow_access = true

  key_vault {
    name                = azurerm_key_vault.workload[each.key].name
    service_endpoint_id = azuredevops_serviceendpoint_azurerm.project[each.key].id
  }

  variable {
    name = "*"
  }
}

resource "azuredevops_pipeline_authorization" "workload_variable_group" {
  for_each = { for each in local.workload_environments : each.key => each if each.devops_create_variable_group }

  project_id  = azuredevops_project.project[each.value.devops_project].id
  resource_id = azuredevops_variable_group.workload[each.key].id

  type = "variablegroup"
}
