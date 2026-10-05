run "validate_complete_scoped_catalog" {
  command = plan

  plan_options {
    target = [terraform_data.repository_analysis_contract]
  }

  assert {
    condition     = length(local.repository_analysis_policies) == 50 && alltrue(values(local.repository_analysis_valid))
    error_message = "All 50 scoped catalog rows must carry valid source profiles or explicit exemptions."
  }

  assert {
    condition     = length(local.repository_analysis_variables) == 142
    error_message = "Expected profile/cadence projection to 46 applicable repositories and build/Sonar recipes to 25 public source repositories."
  }

  assert {
    condition = alltrue([
      for variable in local.repository_analysis_variables :
      !startswith(variable.repository, "xi-") &&
      !can(local.repository_analysis_policies[variable.repository].profile.exemption)
    ])
    error_message = "Excluded and exempt repositories must never receive new analysis variables."
  }

  assert {
    condition = alltrue([
      for name, workload in local.analysis_scoped_workloads :
      workload.github.visibility != "private" || local.repository_analysis_policies[name].sonar == null
    ])
    error_message = "Private repositories must not select public Sonar execution."
  }
}
