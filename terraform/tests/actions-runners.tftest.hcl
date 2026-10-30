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
    })
    error_message = "The initial ARC enrollment must contain only the approved baremetal-workload-template pilot."
  }

  assert {
    condition = (
      local.actions_runner_variables["baremetal-workload-template"].name == "COPILOT_CODE_REVIEW_RUNNER" &&
      local.actions_runner_variables["baremetal-workload-template"].value == "arc-baremetal-workload-template" &&
      alltrue(values(local.actions_runner_enrollments_valid))
    )
    error_message = "The pilot repository must receive the validated Copilot runner scale-set variable."
  }
}
