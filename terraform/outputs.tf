output "workload_resource_groups" {
  description = "Resource groups created per workload environment/location. Keys are '{workload}-{environment}'."
  value = {
    for environment in local.workload_environments :
    environment.key => {
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
  }
}

output "workload_terraform_backends" {
  description = "Terraform backend resources for workloads where configure_for_terraform = true. Keys are '{workload}-{environment}'."
  value = {
    for environment in local.workload_environments :
    environment.key => {
      workload             = environment.workload_name
      environment          = environment.environment_name
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
    if contains(keys(azurerm_resource_group.workload_terraform), environment.key)
  }
}
