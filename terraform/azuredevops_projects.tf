resource "azuredevops_project" "project" {
  for_each = { for each in var.azuredevops_projects : each.name => each }

  name        = each.value.name
  description = each.value.description

  visibility = each.value.visibility

  version_control    = each.value.version_control
  work_item_template = each.value.work_item_template

  features = {
    "boards"       = each.value.features.boards
    "repositories" = each.value.features.repositories
    "pipelines"    = each.value.features.pipelines
    "testplans"    = each.value.features.testplans
    "artifacts"    = each.value.features.artifacts
  }
}

resource "azuread_application" "project" {
  for_each = { for each in var.azuredevops_projects : each.name => each if each.add_nuget_variable_group }

  display_name = format("spn-%s-keyvault-access", lower(each.value.name))

  owners = [
    data.azuread_client_config.current.object_id
  ]

  sign_in_audience = "AzureADMyOrg"
}

resource "azuread_service_principal" "project" {
  for_each = { for each in var.azuredevops_projects : each.name => each if each.add_nuget_variable_group }

  client_id                    = azuread_application.project[each.key].client_id
  app_role_assignment_required = false

  owners = [
    data.azuread_client_config.current.object_id
  ]
}

resource "azurerm_role_assignment" "project" {
  for_each = { for each in var.azuredevops_projects : each.name => each if each.add_nuget_variable_group }

  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azuread_service_principal.project[each.key].object_id
}

resource "azuread_application_federated_identity_credential" "project" {
  for_each = { for each in var.azuredevops_projects : each.name => each if each.add_nuget_variable_group }

  application_id = azuread_application.project[each.key].id
  display_name   = format("ado-%s", lower(each.value.name))
  description    = "Azure DevOps"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://vstoken.dev.azure.com/af603ba1-963b-4eea-962e-9f543ae9813d"
  subject        = "sc://frasermolyneux/${azuredevops_project.project[each.key].name}/${azuread_application.project[each.key].display_name}"
}

resource "azuredevops_serviceendpoint_azurerm" "project" {
  for_each = { for each in var.azuredevops_projects : each.name => each if each.add_nuget_variable_group }

  project_id = azuredevops_project.project[each.key].id

  service_endpoint_name                  = azuread_application.project[each.key].display_name
  service_endpoint_authentication_scheme = "WorkloadIdentityFederation"

  description = "Managed By platform-workloads for Key Vault Access to NuGet secrets"

  credentials {
    serviceprincipalid = azuread_service_principal.project[each.key].client_id
  }

  azurerm_spn_tenantid      = "e56a6947-bb9a-4a6e-846a-1f118d1c3a14"
  azurerm_subscription_id   = data.azurerm_client_config.current.subscription_id
  azurerm_subscription_name = "sub-platform-management"
}

resource "azuredevops_pipeline_authorization" "project" {
  for_each = { for each in var.azuredevops_projects : each.name => each if each.add_nuget_variable_group }

  project_id  = azuredevops_project.project[each.key].id
  resource_id = azuredevops_serviceendpoint_azurerm.project[each.key].id

  type = "endpoint"
}

moved {
  from = azuredevops_variable_group.project
  to   = azuredevops_variable_group.nuget
}

resource "azuredevops_variable_group" "nuget" {
  for_each = { for each in var.azuredevops_projects : each.name => each if each.add_nuget_variable_group }

  project_id  = azuredevops_project.project[each.key].id
  name        = "NuGet"
  description = "Variable group for NuGet secret access"

  allow_access = true

  key_vault {
    name                = azurerm_key_vault.kv.name
    service_endpoint_id = azuredevops_serviceendpoint_azurerm.project[each.key].id
  }

  variable {
    name = "nuget-token"
  }
}

resource "azuredevops_pipeline_authorization" "nuget" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  project_id  = azuredevops_project.project[each.value.devops_project].id
  resource_id = azuredevops_variable_group.nuget[each.value.devops_project].id

  type = "variablegroup"
}

resource "azuredevops_variable_group" "sonarcloud" {
  for_each = { for each in var.azuredevops_projects : each.name => each if each.add_nuget_variable_group }

  project_id  = azuredevops_project.project[each.key].id
  name        = "SonarCloud"
  description = "Variable group for SonarCloud secret access"

  allow_access = true

  key_vault {
    name                = azurerm_key_vault.kv.name
    service_endpoint_id = azuredevops_serviceendpoint_azurerm.project[each.key].id
  }

  variable {
    name = "sonarcloud-token"
  }
}

resource "azuredevops_pipeline_authorization" "sonarcloud" {
  for_each = { for each in local.workload_environments : each.key => each if each.connect_to_devops }

  project_id  = azuredevops_project.project[each.value.devops_project].id
  resource_id = azuredevops_variable_group.sonarcloud[each.value.devops_project].id

  type = "variablegroup"
}
