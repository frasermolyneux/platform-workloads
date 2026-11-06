mock_provider "azurerm" {
  override_during = plan
}
mock_provider "random" {
  override_during = plan
}

override_resource {
  target          = azurerm_storage_account.workload
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.Storage/storageAccounts/test"
  }
}

override_resource {
  target          = azurerm_storage_account.workload["platform-hosting-Development"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.Storage/storageAccounts/testdev"
  }
}

override_resource {
  target          = azurerm_storage_account.workload["platform-hosting-Production"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.Storage/storageAccounts/testprd"
  }
}

run "terraform_enabled_environments_have_private_storage_containers" {
  command = plan

  plan_options {
    target = [
      azurerm_storage_container.workload,
      azurerm_storage_container.workload_tfplan,
    ]
  }

  assert {
    condition = (
      azurerm_storage_account.workload["platform-hosting-Development"].id !=
      azurerm_storage_account.workload["platform-hosting-Production"].id &&
      azurerm_storage_account.workload["platform-hosting-Development"].id !=
      azurerm_storage_account.workload["platform-monitoring-Development"].id &&
      azurerm_storage_account.workload["platform-hosting-Production"].id !=
      azurerm_storage_account.workload["platform-monitoring-Development"].id
    )
    error_message = "The test must use distinct storage account IDs for the selected environments."
  }

  assert {
    condition = (
      length(azurerm_storage_container.workload_tfplan) > 0 &&
      toset(keys(azurerm_storage_container.workload_tfplan)) == toset([
        for environment in local.workload_environments : environment.key
        if environment.configure_for_terraform
      ]) &&
      toset(keys(azurerm_storage_container.workload_tfplan)) == toset(keys(azurerm_storage_container.workload))
    )
    error_message = "Every Terraform-enabled environment, and no other environment, must have both containers."
  }

  assert {
    condition = alltrue([
      for key, container in azurerm_storage_container.workload_tfplan :
      container.name == "tfplan" &&
      container.container_access_type == "private" &&
      container.storage_account_id == azurerm_storage_account.workload[key].id &&
      azurerm_storage_container.workload[key].name == "tfstate" &&
      azurerm_storage_container.workload[key].container_access_type == "private" &&
      azurerm_storage_container.workload[key].storage_account_id == container.storage_account_id
    ])
    error_message = "The tfstate and tfplan containers must be private and use their environment's storage account."
  }
}
