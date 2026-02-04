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
        dynamic "required_check" {
          for_each = try(each.value.rules.required_status_checks, [])
          content {
            context = required_check.value.context
          }
        }
      }
    }

    dynamic "required_pull_request" {
      for_each = try(each.value.rules.required_pull_request, null) != null ? [1] : []
      content {
        required_approving_review_count = try(each.value.rules.required_pull_request.required_approving_review_count, 1)
        dismiss_stale_reviews           = try(each.value.rules.required_pull_request.dismiss_stale_reviews, true)
        require_code_owner_review       = try(each.value.rules.required_pull_request.require_code_owner_review, false)
      }
    }

    dynamic "required_conversation_resolution" {
      for_each = try(each.value.rules.required_conversation_resolution, false) ? [1] : []
      content {}
    }

    dynamic "required_signatures" {
      for_each = try(each.value.rules.required_signatures, false) ? [1] : []
      content {}
    }

    dynamic "linear_history" {
      for_each = try(each.value.rules.linear_history, false) ? [1] : []
      content {}
    }
  }
}
