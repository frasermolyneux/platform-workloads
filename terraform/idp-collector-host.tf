locals {
  idp_collector_host_resource_group = local.workload_environment_resource_groups_map["platform-baremetal-Production-uksouth-rg-platform-baremetal-prd-uksouth"]
}

# Read ARM directly: baremetal already consumes this stack's resource-group outputs.
data "azurerm_arc_machine" "idp_collector_host" {
  name                = "ns346663"
  resource_group_name = local.idp_collector_host_resource_group.name

  lifecycle {
    precondition {
      condition     = lower(var.subscriptions[local.idp_collector_host_resource_group.subscription].subscription_id) == lower(var.subscription_id)
      error_message = "The IDP Arc host lookup must use the baremetal Production subscription; do not resolve a same-named host in another subscription."
    }

    postcondition {
      condition = try(
        self.identity[0].type == "SystemAssigned" &&
        self.identity[0].tenant_id == data.azurerm_client_config.current.tenant_id &&
        can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", self.identity[0].principal_id)),
      false)
      error_message = "The IDP host must have a valid system-assigned Arc identity in the deployment tenant."
    }
  }
}

resource "azurerm_role_assignment" "idp_collector_github_app_reader" {
  scope                = "${azurerm_key_vault.kv.id}/secrets/${azurerm_key_vault_secret.github_app_pem.name}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_arc_machine.idp_collector_host.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
