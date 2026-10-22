locals {
  maps_service_roles = {
    "Maps.Read" = {
      name        = "Maps catalogue reader"
      description = "Read map manifests and download redirect files through the maps API."
    }
    "Maps.Write" = {
      name        = "Maps file manager"
      description = "Manage redirect files through the maps API without changing human permissions or rate limits."
    }
  }
}

resource "random_uuid" "maps_service_role" {
  for_each = local.maps_service_roles
}

resource "azuread_application" "maps_service" {
  display_name     = "app-xi-redirect-manager-prd"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2
  }

  dynamic "app_role" {
    for_each = local.maps_service_roles
    content {
      id                   = random_uuid.maps_service_role[app_role.key].result
      value                = app_role.key
      display_name         = app_role.value.name
      description          = app_role.value.description
      allowed_member_types = ["Application"]
      enabled              = true
    }
  }

  lifecycle {
    ignore_changes = [identifier_uris]
  }
}

resource "azuread_application_identifier_uri" "maps_service" {
  application_id = azuread_application.maps_service.id
  identifier_uri = "api://${azuread_application.maps_service.client_id}"
}

resource "azuread_service_principal" "maps_service" {
  client_id                    = azuread_application.maps_service.client_id
  app_role_assignment_required = true
  owners                       = [data.azuread_client_config.current.object_id]
}

output "maps_service_identity" {
  description = "Secretless maps API identity; consumer stacks assign only the application roles they need."
  value = {
    client_id            = azuread_application.maps_service.client_id
    service_principal_id = azuread_service_principal.maps_service.object_id
    tenant_id            = data.azuread_client_config.current.tenant_id
    identifier_uri       = azuread_application_identifier_uri.maps_service.identifier_uri
    role_ids             = { for name, role in random_uuid.maps_service_role : name => role.result }
  }
}
