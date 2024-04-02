resource "azuredevops_variable_group" "vg" {
  project_id  = data.azuredevops_project.project[var.devops_project].id
  name        = "${var.workload_name}-${var.environment_tag}"
  description = "Variable group for ${var.workload_name}-${var.environment_tag}"

  allow_access = true

  key_vault {
    name                = azurerm_key_vault.kv.name
    service_endpoint_id = azuredevops_serviceendpoint_azurerm.se.id
  }

  // At least one variable is required
  variable {
    name  = "ado_key_vault_name"
    value = azurerm_key_vault.kv.name
  }

  dynamic "variable" {
    for_each = compact(var.key_vault_variables)

    content {
      name = variable.value
    }
  }

  depends_on = [
    azurerm_role_assignment.workload_key_vault_secrets_officer
  ]
}

resource "azuredevops_pipeline_authorization" "vg_auth" {
  project_id  = data.azuredevops_project.project[var.devops_project].id
  resource_id = azuredevops_variable_group.vg.id

  type = "variablegroup"
}
