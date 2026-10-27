mock_provider "github" {}

run "project_only_opted_in_environment_publishers" {
  command = plan

  plan_options {
    target = [github_actions_environment_variable.container_registry_name]
  }

  assert {
    condition = (
      length(github_actions_environment_variable.container_registry_name) == 2 &&
      alltrue([
        for publisher in github_actions_environment_variable.container_registry_name :
        publisher.environment == "Production" &&
        publisher.variable_name == "WORKLOAD_ACR_NAME"
      ])
    )
    error_message = "Registry projection must be opt-in and must not create hosted Development publishing environments."
  }
}
