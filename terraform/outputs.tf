output "workload_resource_groups" {
  description = "Resource groups per workload, nested by environment tag (dev/tst/prd). Access: workload_resource_groups[workload][env_tag]."
  value = {
    for workload_name in distinct([for env in local.workload_environments : env.workload_name]) :
    workload_name => {
      for environment in local.workload_environments :
      environment.environment_tag => {
        workload        = environment.workload_name
        environment     = environment.environment_name
        environment_tag = environment.environment_tag
        subscription_id = data.azurerm_subscription.subscriptions[environment.subscription].id
        resource_groups = {
          for rg in local.workload_environment_resource_groups :
          rg.location => {
            name = azapi_resource.workload_resource_group[rg.key].name
            id   = azapi_resource.workload_resource_group[rg.key].id
            tags = local.workload_environment_resource_groups_map[rg.key].tags
          }
          if rg.workload_environment_key == environment.key
        }
      }
      if environment.workload_name == workload_name
    }
  }
}

output "workload_terraform_backends" {
  description = "Terraform backends per workload, nested by environment tag (dev/tst/prd) for configure_for_terraform=true. Access: workload_terraform_backends[workload][env_tag]."
  value = {
    for workload_name in distinct([for env in local.workload_environments : env.workload_name]) :
    workload_name => {
      for environment in local.workload_environments :
      environment.environment_tag => {
        workload             = environment.workload_name
        environment          = environment.environment_name
        environment_tag      = environment.environment_tag
        subscription_id      = var.subscription_id
        resource_group_name  = azurerm_resource_group.workload_terraform[environment.key].name
        storage_account_name = azurerm_storage_account.workload[environment.key].name
        container_name       = azurerm_storage_container.workload[environment.key].name
        key                  = "terraform.tfstate"
        tenant_id            = "e56a6947-bb9a-4a6e-846a-1f118d1c3a14"
        location             = azurerm_resource_group.workload_terraform[environment.key].location
        storage_account_id   = azurerm_storage_account.workload[environment.key].id
        resource_group_id    = azurerm_resource_group.workload_terraform[environment.key].id
      }
      if environment.workload_name == workload_name && contains(keys(azurerm_resource_group.workload_terraform), environment.key)
    }
  }
}

output "workload_administrative_units" {
  description = "Administrative Units per workload, nested by environment tag (dev/tst/prd). Access: workload_administrative_units[workload][env_tag]. Use administrative_unit_object_id when assigning AU-scoped roles or placing groups in the AU."
  value = {
    for workload_name in distinct([for env in local.workload_environments : env.workload_name]) :
    workload_name => {
      for environment in local.workload_environments :
      environment.environment_tag => {
        workload                      = environment.workload_name
        environment                   = environment.environment_name
        environment_tag               = environment.environment_tag
        administrative_unit_key       = environment.administrative_unit_keys[0]
        administrative_unit_id        = azuread_administrative_unit.platform[environment.administrative_unit_keys[0]].id
        administrative_unit_object_id = azuread_administrative_unit.platform[environment.administrative_unit_keys[0]].object_id
        administrative_unit_name      = azuread_administrative_unit.platform[environment.administrative_unit_keys[0]].display_name
      }
      if environment.workload_name == workload_name && length(environment.administrative_unit_keys) > 0
    }
  }
}

output "workload_service_principals" {
  description = "Workload application and service principal identifiers, nested by environment tag (dev/tst/prd). Access: workload_service_principals[workload][env_tag]."
  value = {
    for workload_name in distinct([for env in local.workload_environments : env.workload_name]) :
    workload_name => {
      for environment in local.workload_environments :
      environment.environment_tag => {
        workload                       = environment.workload_name
        environment                    = environment.environment_name
        environment_tag                = environment.environment_tag
        application_client_id          = azuread_application.workload[environment.key].client_id
        application_object_id          = azuread_application.workload[environment.key].object_id
        service_principal_client_id    = azuread_service_principal.workload[environment.key].client_id
        service_principal_object_id    = azuread_service_principal.workload[environment.key].object_id
        service_principal_display_name = azuread_service_principal.workload[environment.key].display_name
      }
      if environment.workload_name == workload_name
    }
  }
}

output "subscriptions" {
  description = "Master list of all subscriptions managed by platform-workloads. Access: subscriptions[name].subscription_id."
  value       = var.subscriptions
}
