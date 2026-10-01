# Removed blocks for per-workload-environment Azure DevOps resources.
#
# Background: every workload that previously had `devops_project` set has migrated to
# GitHub Actions — there are no `azure-pipelines*.yml` files in any consumer repo. The
# AzDO environments / service connections / variable groups / pipeline authorisations
# created by the deleted `azure-workloads.if-devops.tf` (and the `pipeline_authorization.nuget`
# / `pipeline_authorization.sonarcloud` blocks removed from `azuredevops_projects.tf`) are
# dead weight.
#
# Compounding the issue, the PAT identity ("Global Addy") that the `azuredevops` provider
# uses lost View permission on these specific Pipeline Environments, which broke
# `terraform refresh` (and therefore plan/apply) entirely — see deploy-prd run 24964548130.
#
# Rather than restoring the PAT permissions just to tear these resources down, we forget
# them from Terraform state with `lifecycle { destroy = false }`. The orphaned objects are
# left in the AzDO UI for manual cleanup at leisure (they cost nothing and only clutter the
# project's Pipelines → Environments / Service Connections / Library views).
#
# Apply procedure (one-time, to bypass the failing refresh):
#   terraform plan -refresh=false -out=tfplan -var-file=tfvars/prd.tfvars
#   terraform apply tfplan
# Subsequent runs are clean — these resource addresses are gone from both config and state.

removed {
  from = azuredevops_environment.workload
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_check_exclusive_lock.workload_environment
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_pipeline_authorization.workload_environment
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_serviceendpoint_azurerm.workload
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_pipeline_authorization.workload_auth_to_serviceendpoint
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_variable_group.workload
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_pipeline_authorization.workload_auth_to_variable_group
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_pipeline_authorization.nuget
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_pipeline_authorization.sonarcloud
  lifecycle { destroy = false }
}

# Detach the remaining project-level Azure DevOps resources and their supporting
# Azure/Entra resources. The deployed objects are intentionally preserved for
# manual cleanup after consumers have been confirmed as migrated.

removed {
  from = azuredevops_project.project
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_serviceendpoint_github.github_connection_pipelines
  lifecycle { destroy = false }
}

removed {
  from = azuread_application.project
  lifecycle { destroy = false }
}

removed {
  from = azuread_service_principal.project
  lifecycle { destroy = false }
}

removed {
  from = azurerm_role_assignment.project
  lifecycle { destroy = false }
}

removed {
  from = azuread_application_federated_identity_credential.project
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_serviceendpoint_azurerm.project
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_pipeline_authorization.project
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_variable_group.nuget
  lifecycle { destroy = false }
}

removed {
  from = azuredevops_variable_group.sonarcloud
  lifecycle { destroy = false }
}

removed {
  from = azuread_application_federated_identity_credential.devops_workload
  lifecycle { destroy = false }
}
