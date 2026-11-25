run "validate_complete_scoped_catalog" {
  command = plan

  plan_options {
    target = [terraform_data.repository_analysis_contract]
  }

  assert {
    condition     = length(local.repository_analysis_policies) == 49 && alltrue(values(local.repository_analysis_valid))
    error_message = "All 49 scoped catalog rows must carry valid source profiles or explicit exemptions."
  }

  assert {
    condition = (
      local.analysis_scoped_workloads["beeops"].github.visibility == "private" &&
      local.analysis_scoped_workloads["beeops"].github.auto_init == true &&
      !can(local.analysis_scoped_workloads["beeops"].environments) &&
      local.repository_analysis_policies["beeops"].profile.exemption.kind == "documentation-only"
    )
    error_message = "BeeOps must be an initialized private repository-only workload with a documentation exemption."
  }

  assert {
    condition     = length(local.repository_analysis_variables) == 138
    error_message = "Expected profile/cadence projection to 45 applicable repositories and build/Sonar recipes to 24 public source repositories."
  }

  assert {
    condition = (
      local.analysis_scoped_workloads["platform-tailscale"].github.visibility == "private" &&
      local.repository_analysis_policies["platform-tailscale"].profile.sonar == false &&
      local.repository_analysis_policies["platform-tailscale"].sonar == null &&
      length([
        for variable in local.repository_analysis_variables : variable.name
        if variable.repository == "platform-tailscale"
      ]) == 2 &&
      one([
        for ruleset in local.analysis_scoped_workloads["platform-tailscale"].github.rulesets : ruleset
        if ruleset.name == "main-protection"
      ]).rules.required_status_checks[*].context == ["terraform-plan-prd"]
    )
    error_message = "Tailscale must receive private analysis without public Sonar execution and require its production Terraform plan check."
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
