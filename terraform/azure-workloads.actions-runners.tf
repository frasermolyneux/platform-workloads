locals {
  actions_runner_enrollments = {
    for workload in local.all_workloads : workload.name => {
      repository          = workload.name
      host                = workload.github.actions_runner.host
      scale_set_name      = workload.github.actions_runner.scale_set_name
      copilot_code_review = workload.github.actions_runner.copilot_code_review
    }
    if try(workload.github.actions_runner.enabled, false)
  }

  actions_runner_enrollments_valid = {
    for name, enrollment in local.actions_runner_enrollments : name => try(
      length(setsubtract(
        keys(local.all_workloads[index(local.all_workloads[*].name, name)].github.actions_runner),
        ["enabled", "host", "scale_set_name", "copilot_code_review"]
      )) == 0 &&
      local.all_workloads[index(local.all_workloads[*].name, name)].github.actions_runner.enabled == true &&
      local.all_workloads[index(local.all_workloads[*].name, name)].github.visibility == "private" &&
      can(regex("^[a-z0-9][a-z0-9-]{0,62}$", enrollment.host)) &&
      can(regex("^[a-z0-9][a-z0-9-]{0,44}$", enrollment.scale_set_name)) &&
      enrollment.copilot_code_review == true || enrollment.copilot_code_review == false,
      false
    )
  }

  actions_runner_variables = merge([
    for name, enrollment in local.actions_runner_enrollments : merge(
      {
        "${name}:actions" = {
          repository = name
          name       = "ACTIONS_RUNNER"
          value      = enrollment.scale_set_name
        }
      },
      enrollment.copilot_code_review ? {
        "${name}:copilot" = {
          repository = name
          name       = "COPILOT_CODE_REVIEW_RUNNER"
          value      = enrollment.scale_set_name
        }
      } : {}
    )
  ]...)
}

resource "terraform_data" "actions_runner_contract" {
  input = sha256(jsonencode({
    enrollments = local.actions_runner_enrollments
    variables   = local.actions_runner_variables
  }))

  lifecycle {
    precondition {
      condition     = alltrue(values(local.actions_runner_enrollments_valid))
      error_message = "Actions runner enrollments must target private repositories, use valid host and scale-set names, declare Copilot code review usage, and contain only supported properties."
    }

    precondition {
      condition = (
        length(local.actions_runner_enrollments) ==
        length(distinct([for enrollment in values(local.actions_runner_enrollments) : enrollment.scale_set_name]))
      )
      error_message = "Actions runner scale-set names must be unique across enrolled repositories."
    }
  }
}

resource "github_actions_variable" "actions_runner" {
  for_each = local.actions_runner_variables

  repository = try(local.all_workloads[index(local.all_workloads[*].name, each.value.repository)].github.manage_repository, true) ? (
    github_repository.workload[each.value.repository].name
  ) : each.value.repository
  variable_name = each.value.name
  value         = each.value.value
  depends_on    = [terraform_data.actions_runner_contract]
}

output "actions_runner_enrollments" {
  description = "Private repository ARC enrollments consumed by the bare-metal runner hosts."
  value       = local.actions_runner_enrollments
}
