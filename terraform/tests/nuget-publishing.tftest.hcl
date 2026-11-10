mock_provider "github" {}

run "project_only_active_nuget_publishers" {
  command = plan

  plan_options {
    target = [github_actions_environment_variable.nuget_user]
  }

  assert {
    condition = (
      length(github_repository_environment.nuget) == 12 &&
      toset(keys(github_actions_environment_variable.nuget_user)) == toset(keys(github_repository_environment.nuget)) &&
      alltrue([
        for publisher in github_actions_environment_variable.nuget_user :
        publisher.environment == "NuGet" &&
        publisher.variable_name == "NUGET_USER" &&
        publisher.value == "frasermolyneux"
      ])
    )
    error_message = "All 12 active NuGet publishers must receive the trusted-publishing username."
  }

  assert {
    condition = (
      !contains(keys(github_repository_environment.nuget), "portal-web") &&
      !contains(keys(github_repository_environment.nuget), "portal-environments")
    )
    error_message = "Unused portal repositories must not receive NuGet environments or usernames."
  }
}
