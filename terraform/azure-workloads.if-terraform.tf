resource "azurerm_resource_group" "workload_terraform" {
  for_each = { for each in local.workload_environments : each.key => each if each.configure_for_terraform }

  name     = format("rg-tf-%s-%s-%s-%s", each.value.workload_name, var.environment_map[each.value.environment_name], var.location, var.instance)
  location = var.location

  tags = merge(var.tags, { Workload = each.value.workload_name, Environment = each.value.environment_name })
}

resource "azurerm_storage_account" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.configure_for_terraform }

  name                = format("sa%s", random_id.workload_id[each.key].hex)
  resource_group_name = azurerm_resource_group.workload_terraform[each.key].name
  location            = azurerm_resource_group.workload_terraform[each.key].location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = merge(var.tags, { Workload = each.value.workload_name, Environment = each.value.environment_name })
}

resource "azurerm_storage_container" "workload" {
  for_each = { for each in local.workload_environments : each.key => each if each.configure_for_terraform }

  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.workload[each.key].name
  container_access_type = "private"
}

// Rather annoyingly, we need to allow the service principal to query for storage account keys; even though we're not using them and using OIDC.
resource "azurerm_role_assignment" "workload_storage_blob_key_operator" {
  for_each = { for each in local.workload_environments : each.key => each if each.configure_for_terraform }

  scope                = azurerm_storage_account.workload[each.key].id
  role_definition_name = "Storage Account Key Operator Service Role"
  principal_id         = azuread_service_principal.workload[each.key].object_id
}

resource "azurerm_role_assignment" "workload_storage_blob_contributor" {
  for_each = { for each in local.workload_environments : each.key => each if each.configure_for_terraform }

  scope                = azurerm_storage_account.workload[each.key].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.workload[each.key].object_id
}
