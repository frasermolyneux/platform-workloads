mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000004"
    }
  }

  mock_data "azurerm_arc_machine" {
    defaults = {
      identity = [{
        type         = "SystemAssigned"
        tenant_id    = "00000000-0000-0000-0000-000000000004"
        principal_id = "00000000-0000-0000-0000-000000000002"
      }]
    }
  }
}

mock_provider "azapi" {}
mock_provider "azuread" {}
mock_provider "github" {}
mock_provider "random" {}
mock_provider "time" {}
mock_provider "cloudflare" {}

override_resource {
  target          = azurerm_key_vault.kv
  override_during = plan
  values = {
    id = "/subscriptions/7760848c-794d-4a19-8cb2-52f71a21ac2b/resourceGroups/rg-platform-workloads-prd-uksouth-01/providers/Microsoft.KeyVault/vaults/kv-test"
  }
}

run "grant_only_shared_key_to_confirmed_arc_host" {
  command = plan

  plan_options {
    target = [azurerm_role_assignment.idp_collector_github_app_reader]
  }

  assert {
    condition = (
      data.azurerm_arc_machine.idp_collector_host.name == "ns346663" &&
      data.azurerm_arc_machine.idp_collector_host.resource_group_name == "rg-platform-baremetal-prd-uksouth" &&
      azurerm_role_assignment.idp_collector_github_app_reader.scope == "${azurerm_key_vault.kv.id}/secrets/github-app-pem" &&
      azurerm_role_assignment.idp_collector_github_app_reader.role_definition_name == "Key Vault Secrets User" &&
      azurerm_role_assignment.idp_collector_github_app_reader.principal_id == "00000000-0000-0000-0000-000000000002" &&
      azurerm_role_assignment.idp_collector_github_app_reader.principal_type == "ServicePrincipal"
    )
    error_message = "Only the confirmed host's system identity may read the existing versionless shared-key secret; never grant vault-wide access or read the key into a new data source."
  }
}

run "reject_foreign_tenant_host" {
  command = plan

  override_data {
    target = data.azurerm_arc_machine.idp_collector_host
    values = {
      identity = [{
        type         = "SystemAssigned"
        tenant_id    = "00000000-0000-0000-0000-000000000005"
        principal_id = "00000000-0000-0000-0000-000000000002"
      }]
    }
  }

  plan_options {
    target = [data.azurerm_arc_machine.idp_collector_host]
  }

  expect_failures = [data.azurerm_arc_machine.idp_collector_host]
}

run "reject_missing_system_identity" {
  command = plan

  override_data {
    target = data.azurerm_arc_machine.idp_collector_host
    values = { identity = [] }
  }

  plan_options {
    target = [data.azurerm_arc_machine.idp_collector_host]
  }

  expect_failures = [data.azurerm_arc_machine.idp_collector_host]
}

run "reject_wrong_host_subscription" {
  command = plan

  variables {
    subscription_id = "00000000-0000-0000-0000-000000000003"
  }

  plan_options {
    target = [data.azurerm_arc_machine.idp_collector_host]
  }

  expect_failures = [data.azurerm_arc_machine.idp_collector_host]
}

run "reject_invalid_host_principal" {
  command = plan

  override_data {
    target = data.azurerm_arc_machine.idp_collector_host
    values = {
      identity = [{
        type         = "SystemAssigned"
        tenant_id    = "00000000-0000-0000-0000-000000000004"
        principal_id = "not-a-principal-id"
      }]
    }
  }

  plan_options {
    target = [data.azurerm_arc_machine.idp_collector_host]
  }

  expect_failures = [data.azurerm_arc_machine.idp_collector_host]
}
