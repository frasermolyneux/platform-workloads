locals {
  copilot_code_review_baseline = {
    review_draft_pull_requests = false
    review_on_push             = false
  }

  workload_repository_policies = [
    for workload in local.all_workloads : {
      workload_name     = workload.name
      manage_repository = try(workload.github.manage_repository, true)
      copilot_enabled   = try(workload.github.repository_policy.copilot_code_review.enabled, true)
      rulesets          = try(workload.github.rulesets, [])
    }
  ]

  workload_rulesets = flatten([
    for policy in local.workload_repository_policies : concat(
      [
        for ruleset in policy.rulesets : merge(ruleset, {
          workload_name     = policy.workload_name
          manage_repository = policy.manage_repository
          rules = merge(try(ruleset.rules, {}), {
            copilot_code_review = (
              ruleset.name == "main-protection" && policy.copilot_enabled
              ? local.copilot_code_review_baseline
              : null
            )
          })
        })
      ],
      policy.copilot_enabled && !contains(
        [for ruleset in policy.rulesets : ruleset.name],
        "main-protection"
        ) ? [
        {
          workload_name     = policy.workload_name
          manage_repository = policy.manage_repository
          name              = "main-protection"
          target            = "branch"
          enforcement       = "active"
          includes          = ["~DEFAULT_BRANCH"]
          excludes          = []
          bypass_actors     = []
          rules = {
            copilot_code_review = local.copilot_code_review_baseline
          }
        }
      ] : []
    )
  ])
}

check "copilot_code_review_exceptions_have_reasons" {
  assert {
    condition = alltrue([
      for workload in local.all_workloads :
      try(workload.github.repository_policy.copilot_code_review.enabled, true) ||
      trimspace(try(workload.github.repository_policy.copilot_code_review.exception_reason, "")) != ""
    ])
    error_message = "Repositories excluded from automatic Copilot review must define repository_policy.copilot_code_review.exception_reason."
  }
}

resource "github_repository_ruleset" "workload" {
  for_each = { for ruleset in local.workload_rulesets : format("%s-%s", ruleset.workload_name, ruleset.name) => ruleset }

  name = each.value.name
  repository = (
    each.value.manage_repository
    ? github_repository.workload[each.value.workload_name].name
    : each.value.workload_name
  )
  enforcement = try(each.value.enforcement, "active")
  target      = try(each.value.target, "branch")

  conditions {
    ref_name {
      include = try(each.value.includes, ["refs/heads/main"])
      exclude = try(each.value.excludes, [])
    }
  }

  dynamic "bypass_actors" {
    for_each = try(each.value.bypass_actors, [])
    content {
      actor_id    = bypass_actors.value.actor_id
      actor_type  = bypass_actors.value.actor_type
      bypass_mode = bypass_actors.value.bypass_mode
    }
  }

  rules {
    dynamic "required_status_checks" {
      for_each = length(try(each.value.rules.required_status_checks, [])) > 0 ? [1] : []
      content {
        strict_required_status_checks_policy = try(each.value.rules.strict_required_status_checks_policy, false)
        do_not_enforce_on_create             = try(each.value.rules.do_not_enforce_on_create, false)

        dynamic "required_check" {
          for_each = try(each.value.rules.required_status_checks, [])
          content {
            context        = required_check.value.context
            integration_id = try(required_check.value.integration_id, null)
          }
        }
      }
    }

    dynamic "pull_request" {
      for_each = try(each.value.rules.pull_request, null) != null ? [1] : []
      content {
        allowed_merge_methods             = try(each.value.rules.pull_request.allowed_merge_methods, null)
        dismiss_stale_reviews_on_push     = try(each.value.rules.pull_request.dismiss_stale_reviews_on_push, false)
        require_code_owner_review         = try(each.value.rules.pull_request.require_code_owner_review, false)
        required_approving_review_count   = try(each.value.rules.pull_request.required_approving_review_count, 0)
        required_review_thread_resolution = try(each.value.rules.pull_request.required_review_thread_resolution, false)
        require_last_push_approval        = try(each.value.rules.pull_request.require_last_push_approval, false)
      }
    }

    dynamic "required_code_scanning" {
      for_each = length(try(each.value.rules.required_code_scanning, [])) > 0 ? [1] : []
      content {
        dynamic "required_code_scanning_tool" {
          for_each = try(each.value.rules.required_code_scanning, [])
          content {
            tool                      = required_code_scanning_tool.value.tool
            alerts_threshold          = try(required_code_scanning_tool.value.alerts_threshold, null)
            security_alerts_threshold = try(required_code_scanning_tool.value.security_alerts_threshold, null)
          }
        }
      }
    }

    dynamic "copilot_code_review" {
      for_each = try(each.value.rules.copilot_code_review, null) != null ? [1] : []
      content {
        review_draft_pull_requests = try(each.value.rules.copilot_code_review.review_draft_pull_requests, false)
        review_on_push             = try(each.value.rules.copilot_code_review.review_on_push, false)
      }
    }

    required_signatures     = try(each.value.rules.required_signatures, false)
    required_linear_history = try(each.value.rules.required_linear_history, false)
    non_fast_forward        = try(each.value.rules.non_fast_forward, false)
  }
}
