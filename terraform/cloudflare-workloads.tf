locals {
  cloudflare_tokens = flatten([
    for workload in local.all_workloads : [
      for environment in try(workload.environments, []) : [
        for token in try(environment.cloudflare_tokens, []) : {
          key              = format("%s-%s-%s", workload.name, environment.name, token.name_suffix)
          workload_name    = workload.name
          environment_name = environment.name
          environment_key  = format("%s-%s", workload.name, environment.name)
          token_name       = format("spn-%s-%s-%s", workload.name, lookup(var.environment_map, environment.name, lower(environment.name)), token.name_suffix)
          policies         = token.policies
        }
      ]
    ]
  ])

  cloudflare_zone_names = toset(flatten([
    for token in local.cloudflare_tokens : [
      for policy in token.policies : policy.zone
    ]
  ]))
}

data "cloudflare_api_token_permission_groups" "all" {
  count = length(local.cloudflare_tokens) > 0 ? 1 : 0
}

data "cloudflare_zone" "lookup" {
  for_each = local.cloudflare_zone_names

  name = each.value
}

resource "cloudflare_api_token" "workload" {
  for_each = { for token in local.cloudflare_tokens : token.key => token }

  name = each.value.token_name

  dynamic "policy" {
    for_each = each.value.policies
    content {
      effect = "allow"
      permission_groups = [
        for pg in policy.value.permission_groups :
        data.cloudflare_api_token_permission_groups.all[0].zone[pg]
      ]
      resources = {
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.lookup[policy.value.zone].id}" = "*"
      }
    }
  }
}

resource "github_actions_environment_secret" "cloudflare_token" {
  for_each = { for token in local.cloudflare_tokens : token.key => token }

  repository      = github_repository.workload[each.value.workload_name].name
  environment     = github_repository_environment.workload[each.value.environment_key].environment
  secret_name     = "CLOUDFLARE_API_KEY"
  plaintext_value = cloudflare_api_token.workload[each.key].value
}
