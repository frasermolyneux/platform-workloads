locals {
  status_service_roles = {
    "Status.Reader" = {
      name        = "Status reader"
      description = "Read restricted status evidence and incident drafts."
      members     = ["User"]
    }
    "Status.Operator" = {
      name        = "Status operator"
      description = "Publish status incidents and maintenance updates."
      members     = ["User"]
    }
    "Status.Ingest" = {
      name        = "Status evidence ingestion"
      description = "Submit private Azure Monitor evidence without public publishing access."
      members     = ["Application"]
    }
  }
}

variable "status_operator_user_principal_name" {
  description = "Explicitly approved Entra user for status operations; no group or tenant-wide operator assignment."
  type        = string
  nullable    = false
}

data "azuread_user" "status_operator" {
  user_principal_name = var.status_operator_user_principal_name
}

resource "random_uuid" "status_service_role" {
  for_each = local.status_service_roles
}

resource "random_uuid" "status_service_scope" {}

resource "azuread_application" "status_service" {
  display_name     = "app-platform-status-web"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  single_page_application {
    redirect_uris = [
      "https://mxstatus.io/ops",
      "https://status.xtremeidiots.com/ops",
    ]
  }

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      id                         = random_uuid.status_service_scope.result
      value                      = "Status.Access"
      type                       = "User"
      enabled                    = true
      admin_consent_display_name = "Access status operations"
      admin_consent_description  = "Access status operations subject to an explicitly assigned reader or operator role."
      user_consent_display_name  = "Access status operations"
      user_consent_description   = "Access the status service using your assigned role."
    }
  }

  dynamic "app_role" {
    for_each = local.status_service_roles
    content {
      id                   = random_uuid.status_service_role[app_role.key].result
      value                = app_role.key
      display_name         = app_role.value.name
      description          = app_role.value.description
      allowed_member_types = app_role.value.members
      enabled              = true
    }
  }

  lifecycle {
    ignore_changes = [identifier_uris]
  }
}

resource "azuread_application_identifier_uri" "status_service" {
  application_id = azuread_application.status_service.id
  identifier_uri = "api://${azuread_application.status_service.client_id}"
}

resource "azuread_service_principal" "status_service" {
  client_id                    = azuread_application.status_service.client_id
  app_role_assignment_required = true
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "azuread_app_role_assignment" "status_operator" {
  app_role_id         = random_uuid.status_service_role["Status.Operator"].result
  principal_object_id = data.azuread_user.status_operator.object_id
  resource_object_id  = azuread_service_principal.status_service.object_id
}

resource "azuread_service_principal_delegated_permission_grant" "status_operator" {
  service_principal_object_id          = azuread_service_principal.status_service.object_id
  resource_service_principal_object_id = azuread_service_principal.status_service.object_id
  user_object_id                       = data.azuread_user.status_operator.object_id
  claim_values                         = ["Status.Access"]
}

resource "github_actions_environment_variable" "status_service_client_id" {
  repository    = github_repository.workload["platform-status-web"].name
  environment   = github_repository_environment.workload["platform-status-web-Production"].environment
  variable_name = "STATUS_CLIENT_ID"
  value         = azuread_application.status_service.client_id
}

resource "github_actions_environment_variable" "status_service_object_id" {
  repository    = github_repository.workload["platform-status-web"].name
  environment   = github_repository_environment.workload["platform-status-web-Production"].environment
  variable_name = "STATUS_APPLICATION_OBJECT_ID"
  value         = azuread_application.status_service.object_id
}

output "status_service_identity" {
  description = "Secretless identity metadata for status runtime and monitoring configuration."
  value = {
    client_id            = azuread_application.status_service.client_id
    application_id       = azuread_application.status_service.object_id
    service_principal_id = azuread_service_principal.status_service.object_id
    tenant_id            = data.azuread_client_config.current.tenant_id
    role_ids             = { for name, role in random_uuid.status_service_role : name => role.result }
    scope                = "${azuread_application_identifier_uri.status_service.identifier_uri}/Status.Access"
  }
}
