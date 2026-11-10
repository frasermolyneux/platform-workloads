mock_provider "github" {}

run "project_only_active_nuget_publishers" {
  command = plan

  plan_options {
    target = [github_actions_environment_variable.nuget_user]
  }

  assert {
    condition = (
      toset(keys(github_repository_environment.nuget)) == toset([
        "api-client-abstractions",
        "cod-demo-reader",
        "dotnet-caching",
        "geo-location",
        "invision-api-client",
        "observability-appinsights",
        "observability-opentelemetry",
        "platform-notifications",
        "portal-repository",
        "portal-server-events",
        "portal-servers-integration",
        "xi-redirect-manager",
      ]) &&
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
