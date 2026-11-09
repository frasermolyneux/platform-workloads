locals {
  cost_budget_fields = ["monthly_budget", "actual_thresholds", "forecast_thresholds", "contact_emails", "rationale", "scope", "budget_name", "start_date"]
  cost_budget_declarations_valid = alltrue(flatten([
    for workload in local.all_workloads : concat(
      [try(length(setsubtract(keys(workload.cost_budget), local.cost_budget_fields)) == 0, !can(workload.cost_budget))],
      [for environment in try(workload.environments, []) :
        try(length(setsubtract(keys(environment.cost_budget), local.cost_budget_fields)) == 0, !can(environment.cost_budget))
      ]
    )
  ]))

  subscription_cost_budget_policies = {
    for alias, subscription in var.subscriptions : alias => {
      monthly_budget      = subscription.monthly_budget
      subscription_id     = subscription.subscription_id
      scope               = "/subscriptions/${subscription.subscription_id}"
      budget_name         = coalesce(try(subscription.cost_budget.budget_name, null), "budget-${subscription.name}")
      start_date          = coalesce(try(subscription.cost_budget.start_date, null), "2026-04-01T00:00:00Z")
      actual_thresholds   = coalesce(try(subscription.cost_budget.actual_thresholds, null), var.cost_budget_defaults.actual_thresholds)
      forecast_thresholds = coalesce(try(subscription.cost_budget.forecast_thresholds, null), var.cost_budget_defaults.forecast_thresholds)
      contact_emails      = coalesce(try(subscription.cost_budget.contact_emails, null), var.cost_budget_defaults.contact_emails)
      rationale           = try(subscription.cost_budget.rationale, null)
    } if subscription.monthly_budget != null
  }

  workload_cost_budget_policies = {
    for environment in local.workload_environments : environment.key => {
      workload        = environment.workload_name
      environment     = environment.environment_name
      environment_tag = environment.environment_tag
      monthly_budget  = try(environment.cost_budget.monthly_budget, null)
      subscription_id = try(var.subscriptions[environment.subscription].subscription_id, null)
      scope = try(environment.cost_budget.scope, "subscription") == "resource-group" ? try(
        "/subscriptions/${var.subscriptions[environment.subscription].subscription_id}/resourceGroups/${one([
          for resource_group in local.workload_environment_resource_groups :
          resource_group.name if resource_group.workload_environment_key == environment.key
        ])}", null
      ) : try("/subscriptions/${var.subscriptions[environment.subscription].subscription_id}", null)
      budget_name         = try(environment.cost_budget.budget_name, "${environment.workload_name}-${environment.environment_tag}-monthly")
      start_date          = try(environment.cost_budget.start_date, var.cost_budget_defaults.start_date)
      actual_thresholds   = try(environment.cost_budget.actual_thresholds, var.cost_budget_defaults.actual_thresholds)
      forecast_thresholds = try(environment.cost_budget.forecast_thresholds, var.cost_budget_defaults.forecast_thresholds)
      contact_emails      = try(environment.cost_budget.contact_emails, var.cost_budget_defaults.contact_emails)
      rationale           = try(environment.cost_budget.rationale, null)
      resource_group_names = sort(distinct([
        for resource_group in local.workload_environment_resource_groups :
        resource_group.name if resource_group.workload_environment_key == environment.key
      ]))
    } if length(coalesce(environment.cost_budget, {})) > 0
  }

  cost_budget_policies = {
    version               = 1
    subscriptions         = local.subscription_cost_budget_policies
    workload_environments = local.workload_cost_budget_policies
  }

  cost_budget_exemptions = {
    for environment in local.workload_environments : environment.key => environment.cost_budget_exemption
    if environment.cost_budget_exemption != null
  }

  cost_budget_policies_valid = alltrue([
    for policy in concat(values(local.subscription_cost_budget_policies), values(local.workload_cost_budget_policies), [
      merge(var.cost_budget_defaults, { monthly_budget = 1, subscription_id = var.subscription_id, budget_name = "defaults" })
      ]) : try(
      policy.monthly_budget > 0 && policy.monthly_budget == tonumber(policy.monthly_budget) &&
      policy.budget_name == tostring(policy.budget_name) &&
      can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,62}$", policy.budget_name)) &&
      can(regex("^[0-9]{4}-(0[1-9]|1[0-2])-01T00:00:00Z$", policy.start_date)) &&
      can(formatdate("YYYY-MM-DD", policy.start_date)) &&
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", policy.subscription_id)) &&
      length(policy.actual_thresholds) + length(policy.forecast_thresholds) > 0 &&
      length(policy.actual_thresholds) + length(policy.forecast_thresholds) <= 5 &&
      length(distinct(policy.actual_thresholds)) == length(policy.actual_thresholds) &&
      length(distinct(policy.forecast_thresholds)) == length(policy.forecast_thresholds) &&
      alltrue([for threshold in concat(policy.actual_thresholds, policy.forecast_thresholds) :
        threshold == tonumber(threshold) && threshold > 0 && threshold <= 1000
      ]) &&
      length(policy.contact_emails) > 0 && length(policy.contact_emails) <= 5 &&
      length(distinct(policy.contact_emails)) == length(policy.contact_emails) &&
      alltrue([for email in policy.contact_emails : email == tostring(email) && can(regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", email))]),
    false)
  ])
}

resource "terraform_data" "cost_budget_contract" {
  input = sha256(jsonencode({
    policies   = local.cost_budget_policies
    exemptions = local.cost_budget_exemptions
  }))

  lifecycle {
    precondition {
      condition = local.cost_budget_declarations_valid && local.cost_budget_policies_valid && alltrue([
        for policy in values(local.workload_cost_budget_policies) :
        try(policy.rationale == tostring(policy.rationale) && length(trimspace(policy.rationale)) > 0 && length(policy.resource_group_names) > 0 && policy.scope != null, false)
        ]) && alltrue([
        for environment in local.workload_environments :
        contains(["subscription", "resource-group"], try(environment.cost_budget.scope, "subscription"))
        ]) && length(distinct([
          for policy in concat(values(local.subscription_cost_budget_policies), values(local.workload_cost_budget_policies)) :
          try(lower("${policy.scope}/providers/Microsoft.Consumption/budgets/${policy.budget_name}"), null)
      ])) == length(local.subscription_cost_budget_policies) + length(local.workload_cost_budget_policies)
      error_message = "Cost budgets require supported fields, positive numeric amounts, unique scope/name identities, valid subscriptions, first-of-month UTC start dates, 1-5 unique alerts (0 < percent <= 1000) and 1-5 valid recipients. Workloads require a rationale and non-empty RG filter; resource-group scope requires exactly one RG."
    }

    precondition {
      condition = alltrue([
        for environment in local.workload_environments :
        contains(keys(local.workload_cost_budget_policies), environment.key) ? environment.cost_budget_exemption == null : try(length(trimspace(environment.cost_budget_exemption)) > 0, false)
      ])
      error_message = "Every workload environment requires either a cost_budget policy or an explicit non-empty cost_budget_exemption, never both."
    }
  }
}
