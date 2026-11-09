variable "subscriptions" {
  type = any
}

run "catalog_budget_contract" {
  command = plan

  plan_options {
    target = [terraform_data.cost_budget_contract]
  }

  assert {
    condition = (
      output.cost_budget_policies.version == 1 &&
      length(local.subscription_cost_budget_policies) == length([for subscription in var.subscriptions : subscription if subscription.monthly_budget != null]) &&
      length(local.workload_cost_budget_policies) + length(local.cost_budget_exemptions) == length(local.workload_environments)
    )
    error_message = "Version 1 must include every configured subscription budget and account for every workload environment through a policy or exemption."
  }

  assert {
    condition = alltrue([
      for alias, total in {
        for alias, subscription in var.subscriptions : alias => sum(concat([0], [
          for policy in values(local.workload_cost_budget_policies) : policy.monthly_budget
          if policy.subscription_id == subscription.subscription_id
        ]))
      } :
      var.subscriptions[alias].monthly_budget >= total + max(5, ceil(total * 0.20))
    ])
    error_message = "Initial subscription budgets must cover workload allowances plus at least 20% (minimum GBP 5) shared/unallocated headroom."
  }

  assert {
    condition = length(distinct(flatten([
      for policy in values(local.workload_cost_budget_policies) : [
        for name in policy.resource_group_names : lower("${policy.subscription_id}/${name}")
      ]
      ]))) == length(flatten([
      for policy in values(local.workload_cost_budget_policies) : policy.resource_group_names
    ]))
    error_message = "Workload RG filters must not overlap within a subscription, so allowance totals do not double-count a shared group."
  }

  assert {
    condition = (
      length(local.workload_cost_budget_policies["platform-sitewatch-func-Production"].resource_group_names) == 3 &&
      length(local.workload_environments) == length(local.workload_cost_budget_policies) + length(local.cost_budget_exemptions) &&
      contains(keys(local.cost_budget_exemptions), "platform-landing-zones-Production")
    )
    error_message = "All environments must be accounted for and a multi-region workload must retain every declared RG in its single budget filter."
  }

  assert {
    condition = alltrue([
      for policy in concat(values(local.subscription_cost_budget_policies), values(local.workload_cost_budget_policies)) :
      policy.contact_emails == tolist(["frasermolyneux@mx-mail.io"]) &&
      tolist(policy.actual_thresholds) == tolist([50, 80, 100]) &&
      tolist(policy.forecast_thresholds) == tolist([100])
    ])
    error_message = "Every policy must inherit the explicit recipient and actual/forecast defaults."
  }

  assert {
    condition = (
      local.workload_cost_budget_policies["portal-core-Production"].monthly_budget == 85 &&
      local.workload_cost_budget_policies["portal-core-Development"].monthly_budget == 35 &&
      local.workload_cost_budget_policies["portal-environments-Production"].monthly_budget == 35 &&
      local.workload_cost_budget_policies["portal-environments-Development"].monthly_budget == 5 &&
      local.workload_cost_budget_policies["platform-notifications-Production"].monthly_budget == 5 &&
      local.workload_cost_budget_policies["platform-notifications-Development"].monthly_budget == 5
    )
    error_message = "Environment amounts must override workload defaults without using the notifications incident as a recurring baseline."
  }

  assert {
    condition = (
      local.workload_cost_budget_policies["platform-radar-Production"].budget_name == "radar-monthly" &&
      local.workload_cost_budget_policies["platform-radar-Production"].scope == "/subscriptions/7760848c-794d-4a19-8cb2-52f71a21ac2b/resourceGroups/rg-platform-radar-prd-uksouth" &&
      local.workload_cost_budget_policies["platform-developer-portal-Production"].budget_name == "idp-monthly-notification" &&
      local.workload_cost_budget_policies["platform-developer-portal-Production"].scope == "/subscriptions/7760848c-794d-4a19-8cb2-52f71a21ac2b/resourceGroups/rg-platform-developer-portal-prd-uksouth" &&
      local.workload_cost_budget_policies["platform-developer-portal-Production"].start_date == "2026-10-01T00:00:00Z"
    )
    error_message = "Legacy Radar and IDP budget names, resource-group scopes and start dates must be preserved for adoption."
  }

  assert {
    condition = (
      local.workload_cost_budget_policies["portal-core-Production"].resource_group_names == tolist(["rg-portal-core-prd-uksouth"]) &&
      local.workload_cost_budget_policies["portal-core-Production"].scope == "/subscriptions/32444f38-32f4-409f-889c-8e8aa2b5b4d1" &&
      local.subscription_cost_budget_policies["sub-platform-management"].budget_name == "budget-sub-platform-management" &&
      local.subscription_cost_budget_policies["sub-platform-management"].start_date == "2026-04-01T00:00:00Z"
    )
    error_message = "New workloads must have an explicit RG filter, while legacy subscription identities remain unchanged."
  }
}

run "subscription_override" {
  command = plan

  variables {
    subscriptions = merge(var.subscriptions, {
      sub-platform-shared = merge(var.subscriptions["sub-platform-shared"], {
        monthly_budget = 100
        cost_budget = {
          actual_thresholds   = [75, 100]
          forecast_thresholds = []
          contact_emails      = ["costs@example.com"]
          budget_name         = "example-custom"
          start_date          = "2026-11-01T00:00:00Z"
          rationale           = "Explicit subscription override."
        }
      })
    })
  }

  plan_options {
    target = [terraform_data.cost_budget_contract]
  }

  assert {
    condition = (
      local.subscription_cost_budget_policies["sub-platform-shared"].monthly_budget == 100 &&
      tolist(local.subscription_cost_budget_policies["sub-platform-shared"].actual_thresholds) == tolist([75, 100]) &&
      length(local.subscription_cost_budget_policies["sub-platform-shared"].forecast_thresholds) == 0 &&
      local.subscription_cost_budget_policies["sub-platform-shared"].contact_emails == tolist(["costs@example.com"]) &&
      local.subscription_cost_budget_policies["sub-platform-shared"].budget_name == "example-custom"
    )
    error_message = "Explicit subscription policy overrides must replace defaults, including an empty forecast alert list."
  }
}

run "reject_duplicate_alerts" {
  command = plan

  variables {
    cost_budget_defaults = {
      actual_thresholds   = [50, 50, 100]
      forecast_thresholds = [100]
      contact_emails      = ["frasermolyneux@mx-mail.io"]
      start_date          = "2026-11-01T00:00:00Z"
    }
  }

  plan_options {
    target = [terraform_data.cost_budget_contract]
  }

  expect_failures = [terraform_data.cost_budget_contract]
}

run "reject_invalid_recipient" {
  command = plan

  variables {
    cost_budget_defaults = {
      actual_thresholds   = [50, 80, 100]
      forecast_thresholds = [100]
      contact_emails      = ["not-an-email"]
      start_date          = "2026-11-01T00:00:00Z"
    }
  }

  plan_options {
    target = [terraform_data.cost_budget_contract]
  }

  expect_failures = [terraform_data.cost_budget_contract]
}

run "reject_invalid_start_date" {
  command = plan

  variables {
    cost_budget_defaults = {
      actual_thresholds   = [50, 80, 100]
      forecast_thresholds = [100]
      contact_emails      = ["frasermolyneux@mx-mail.io"]
      start_date          = "2026-11-02T00:00:00Z"
    }
  }

  plan_options {
    target = [terraform_data.cost_budget_contract]
  }

  expect_failures = [terraform_data.cost_budget_contract]
}

run "reject_excessive_alert_count" {
  command = plan

  variables {
    cost_budget_defaults = {
      actual_thresholds   = [20, 40, 60, 80, 100]
      forecast_thresholds = [100]
      contact_emails      = ["frasermolyneux@mx-mail.io"]
      start_date          = "2026-11-01T00:00:00Z"
    }
  }

  plan_options {
    target = [terraform_data.cost_budget_contract]
  }

  expect_failures = [terraform_data.cost_budget_contract]
}

run "reject_out_of_range_threshold" {
  command = plan

  variables {
    cost_budget_defaults = {
      actual_thresholds   = [0, 1001]
      forecast_thresholds = []
      contact_emails      = ["frasermolyneux@mx-mail.io"]
      start_date          = "2026-11-01T00:00:00Z"
    }
  }

  plan_options {
    target = [terraform_data.cost_budget_contract]
  }

  expect_failures = [terraform_data.cost_budget_contract]
}

run "reject_nonpositive_subscription_budget" {
  command = plan

  variables {
    subscriptions = {
      invalid = {
        name            = "invalid"
        subscription_id = "00000000-0000-0000-0000-000000000001"
        environment     = "prd"
        monthly_budget  = 0
      }
    }
  }

  plan_options {
    target = [terraform_data.cost_budget_contract]
  }

  expect_failures = [var.subscriptions]
}
