resource "azuread_application" "status_monitoring_reader" {
  display_name     = "app-platform-status-monitoring-reader"
  sign_in_audience = "AzureADMyOrg"
  owners = [
    data.azuread_client_config.current.object_id,
    azuread_service_principal.workload["platform-monitoring-Production"].object_id,
  ]
}

resource "azuread_service_principal" "status_monitoring_reader" {
  client_id = azuread_application.status_monitoring_reader.client_id
  owners = [
    data.azuread_client_config.current.object_id,
    azuread_service_principal.workload["platform-monitoring-Production"].object_id,
  ]
}

variable "status_monitoring_resource_ids" {
  description = "Exact Application Insights resource scopes readable by the status monitoring consumer; never workspace, subscription or resource-group scopes."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.status_monitoring_resource_ids :
      can(regex("(?i)^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Insights/components/[^/]+$", id))
    ])
    error_message = "Status monitoring reader scopes must be exact Application Insights resource IDs."
  }
}

resource "azurerm_role_assignment" "status_monitoring_reader" {
  for_each             = var.status_monitoring_resource_ids
  scope                = each.value
  role_definition_name = "Monitoring Reader"
  principal_id         = azuread_service_principal.status_monitoring_reader.object_id
  principal_type       = "ServicePrincipal"
}

resource "github_actions_environment_variable" "status_monitoring_reader_client_id" {
  repository    = github_repository.workload["platform-status-web"].name
  environment   = github_repository_environment.workload["platform-status-web-Production"].environment
  variable_name = "STATUS_MONITORING_READER_CLIENT_ID"
  value         = azuread_application.status_monitoring_reader.client_id
}

resource "github_actions_environment_variable" "status_monitoring_reader_object_id" {
  repository    = github_repository.workload["platform-status-web"].name
  environment   = github_repository_environment.workload["platform-status-web-Production"].environment
  variable_name = "STATUS_MONITORING_READER_APPLICATION_OBJECT_ID"
  value         = azuread_application.status_monitoring_reader.object_id
}

output "status_monitoring_reader_identity" {
  description = "Dedicated monitoring reader metadata; certificate private keys must remain outside Terraform state."
  value = {
    client_id            = azuread_application.status_monitoring_reader.client_id
    application_id       = azuread_application.status_monitoring_reader.object_id
    service_principal_id = azuread_service_principal.status_monitoring_reader.object_id
    tenant_id            = data.azuread_client_config.current.tenant_id
    resource_ids         = var.status_monitoring_resource_ids
  }
}
