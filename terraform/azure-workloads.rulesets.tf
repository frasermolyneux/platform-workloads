locals {
  workload_rulesets = flatten([
    for workload in local.all_workloads : [
      for ruleset in try(workload.rulesets, []) : merge(ruleset, {
        workload_name = workload.name
      })
    ]
  ])
}

resource "github_repository_ruleset" "workload" {
  for_each = { for ruleset in local.workload_rulesets : format("%s-%s", ruleset.workload_name, ruleset.name) => ruleset }

  name        = each.value.name
  repository  = github_repository.workload[each.value.workload_name].name
  enforcement = try(each.value.enforcement, "active")
  target      = try(each.value.target, "branch")

  conditions {
    ref_name {
      include = try(each.value.includes, ["refs/heads/main"])
      exclude = try(each.value.excludes, [])
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

    required_signatures     = try(each.value.rules.required_signatures, false)
    required_linear_history = try(each.value.rules.required_linear_history, false)
  }
}
