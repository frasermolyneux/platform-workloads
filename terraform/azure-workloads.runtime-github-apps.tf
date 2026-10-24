locals {
  runtime_github_apps = merge({}, [
    for workload in local.all_workloads : {
      for name, app in try(workload.github.runtime_apps, {}) :
      "${workload.name}/${name}" => merge(app, {
        workload_name   = workload.name
        app_name        = name
        variable_prefix = "GH_${upper(replace(name, "-", "_"))}"
      })
    }
  ]...)
  runtime_github_apps_valid = {
    for key, app in local.runtime_github_apps : key => try(
      length(setsubtract(keys(app), [
        "display_name", "description", "owner", "owner_type", "homepage_url", "environment",
        "repositories", "repository_permissions", "key_vault_secret_name", "registration",
        "workload_name", "app_name", "variable_prefix"
      ])) == 0 &&
      can(regex("^[a-z][a-z0-9-]*$", app.app_name)) &&
      contains(["User", "Organization"], app.owner_type) &&
      can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", app.owner)) &&
      can(regex("^[A-Za-z0-9-]{1,127}$", app.key_vault_secret_name)) &&
      contains(["dev", "tst", "prd"], app.environment) &&
      startswith(app.homepage_url, "https://") &&
      length(trimspace(app.display_name)) > 0 && length(trimspace(app.description)) > 0 &&
      length(app.repository_permissions) > 0 &&
      alltrue([for value in values(app.repository_permissions) : contains(["read", "write"], value)]) &&
      length(app.repositories) > 0 && length(distinct(app.repositories)) == length(app.repositories) &&
      alltrue([for name in app.repositories : can(regex("^[A-Za-z0-9_.-]+$", name))]) &&
      (app.registration == null ? true : (
        length(setsubtract(keys(app.registration), ["app_id", "installation_id", "slug"])) == 0 &&
        can(regex("^[1-9][0-9]*$", app.registration.app_id)) &&
        can(regex("^[a-z0-9][a-z0-9-]*$", app.registration.slug)) &&
        (app.registration.installation_id == null ? true : can(regex("^[1-9][0-9]*$", app.registration.installation_id)))
      )),
    false)
  }
  registered_runtime_github_apps = {
    for key, app in local.runtime_github_apps : key => app
    if try(app.registration.installation_id != null, false)
  }
  runtime_github_app_variables = merge({}, [
    for key, app in local.registered_runtime_github_apps : {
      for suffix, value in {
        APP_ID          = app.registration.app_id
        INSTALLATION_ID = app.registration.installation_id
        APP_SLUG        = app.registration.slug
        } : "${key}/${suffix}" => {
        repository = app.workload_name
        name       = "${app.variable_prefix}_${suffix}"
        value      = value
      }
    }
  ]...)
}

resource "terraform_data" "runtime_github_apps_contract" {
  input = {
    apps      = local.runtime_github_apps
    variables = local.runtime_github_app_variables
  }

  lifecycle {
    precondition {
      condition     = alltrue(values(local.runtime_github_apps_valid))
      error_message = "Runtime GitHub Apps must declare valid account, repository, permission, Key Vault and registration metadata."
    }
    precondition {
      condition = length(distinct([
        for app in values(local.runtime_github_apps) :
        "${app.workload_name}/${app.environment}/${app.key_vault_secret_name}"
      ])) == length(local.runtime_github_apps)
      error_message = "Each runtime GitHub App must have its own workload Key Vault secret."
    }
  }
}

resource "github_actions_variable" "runtime_github_app" {
  for_each = local.runtime_github_app_variables

  repository    = each.value.repository
  variable_name = each.value.name
  value         = each.value.value

  depends_on = [terraform_data.runtime_github_apps_contract]
}

output "workload_runtime_github_apps" {
  description = "Non-secret runtime GitHub App declarations and registration metadata. Private keys stay in workload Key Vaults, outside Terraform state."
  value       = local.runtime_github_apps
}
