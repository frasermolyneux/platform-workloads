run "validate_actions_runner_projection" {
  command = plan

  plan_options {
    target = [terraform_data.actions_runner_contract]
  }

  assert {
    condition = toset(keys(local.actions_runner_enrollments)) == toset([
      "41-bovet-street",
      "baremetal-workload-template",
      "bishops-bees",
      "bishops-bees-staging",
      "bqba",
      "dm-electrical-services",
      "platform-developer-portal",
      "platform-radar",
      "xi-arcade",
      "xi-bank",
      "xi-casino",
      "xi-cdn",
      "xi-dailygames",
      "xi-forums",
      "xi-forums-test",
      "xi-freezetag-stats",
      "xi-powerball",
      "xi-redirect",
      "xi-redirect-manager",
      "xi-teamspeak",
    ])
    error_message = "ARC enrollment must contain every active private repository except the bare-metal control repositories."
  }

  assert {
    condition = alltrue([
      for name, enrollment in local.actions_runner_enrollments :
      enrollment.repository == name &&
      enrollment.host == "ns346663" &&
      enrollment.scale_set_name == "arc-${name}"
    ])
    error_message = "Each private repository must use its repository-scoped ns346663 ARC scale set."
  }

  assert {
    condition = (
      length(local.actions_runner_variables) == 39 &&
      alltrue([
        for name in keys(local.actions_runner_enrollments) :
        local.actions_runner_variables["${name}:actions"].name == "ACTIONS_RUNNER" &&
        local.actions_runner_variables["${name}:actions"].value == "arc-${name}"
      ]) &&
      alltrue([
        for name in setsubtract(toset(keys(local.actions_runner_enrollments)), toset(["41-bovet-street"])) :
        local.actions_runner_variables["${name}:copilot"].name == "COPILOT_CODE_REVIEW_RUNNER" &&
        local.actions_runner_variables["${name}:copilot"].value == "arc-${name}"
      ]) &&
      !contains(keys(local.actions_runner_variables), "41-bovet-street:copilot") &&
      alltrue(values(local.actions_runner_enrollments_valid))
    )
    error_message = "Each repository must receive ACTIONS_RUNNER, with the Copilot alias projected only where enabled."
  }
}
