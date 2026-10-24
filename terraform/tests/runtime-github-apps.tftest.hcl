run "unregistered_apps_do_not_project_incomplete_credentials" {
  command = plan

  plan_options {
    target = [terraform_data.runtime_github_apps_contract]
  }

  assert {
    condition     = alltrue(values(local.runtime_github_apps_valid))
    error_message = "Every declared runtime GitHub App must satisfy the reviewed bootstrap contract."
  }

  assert {
    condition = alltrue([
      for key, app in local.runtime_github_apps :
      app.registration != null || !contains(keys(local.registered_runtime_github_apps), key)
    ])
    error_message = "A declaration without verified registration must never project runtime App variables."
  }

  assert {
    condition = alltrue([
      for variable in values(local.runtime_github_app_variables) :
      !endswith(variable.name, "_PEM") && !endswith(variable.name, "_TOKEN")
    ])
    error_message = "Runtime private keys and tokens must never be projected through Terraform."
  }
}
