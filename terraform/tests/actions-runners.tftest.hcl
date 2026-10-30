run "validate_actions_runner_projection" {
  command = plan

  plan_options {
    target = [terraform_data.actions_runner_contract]
  }

  assert {
    condition = jsonencode(local.actions_runner_enrollments) == jsonencode({
      baremetal-workload-template = {
        repository          = "baremetal-workload-template"
        host                = "ns346663"
        scale_set_name      = "arc-baremetal-workload-template"
        copilot_code_review = true
      }
      platform-radar = {
        repository          = "platform-radar"
        host                = "ns346663"
        scale_set_name      = "arc-platform-radar"
        copilot_code_review = true
      }
    })
    error_message = "ARC enrollment must contain exactly the approved pilot and platform-radar repositories."
  }

  assert {
    condition = (
      local.actions_runner_variables["baremetal-workload-template"].name == "COPILOT_CODE_REVIEW_RUNNER" &&
      local.actions_runner_variables["baremetal-workload-template"].value == "arc-baremetal-workload-template" &&
      local.actions_runner_variables["platform-radar"].name == "COPILOT_CODE_REVIEW_RUNNER" &&
      local.actions_runner_variables["platform-radar"].value == "arc-platform-radar" &&
      alltrue(values(local.actions_runner_enrollments_valid))
    )
    error_message = "Each approved repository must receive its validated Copilot runner scale-set variable."
  }
}
