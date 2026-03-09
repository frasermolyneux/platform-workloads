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

  cloudflare_permission_group_names = toset(flatten([
    for token in local.cloudflare_tokens : [
      for policy in token.policies : policy.permission_groups
    ]
  ]))

  cloudflare_permission_group_ids = {
    for name in local.cloudflare_permission_group_names :
    name => data.cloudflare_api_token_permission_groups_list.lookup[name].result[0].id
  }
}

data "cloudflare_api_token_permission_groups_list" "lookup" {
  for_each = length(local.cloudflare_tokens) > 0 ? local.cloudflare_permission_group_names : toset([])

  name = urlencode(each.value)
}

data "cloudflare_zone" "lookup" {
  for_each = local.cloudflare_zone_names

  filter = {
    name = each.value
  }
}

resource "cloudflare_api_token" "workload" {
  for_each = { for token in local.cloudflare_tokens : token.key => token }

  name = each.value.token_name

  policies = [
    for policy in each.value.policies : {
      effect = "allow"
      permission_groups = [
        for pg in policy.permission_groups : {
          id = local.cloudflare_permission_group_ids[pg]
        }
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.lookup[policy.zone].id}" = "*"
      })
    }
  ]
}

resource "github_actions_environment_secret" "cloudflare_token" {
  for_each = { for token in local.cloudflare_tokens : token.key => token }

  repository      = github_repository.workload[each.value.workload_name].name
  environment     = github_repository_environment.workload[each.value.environment_key].environment
  secret_name     = "CLOUDFLARE_API_KEY"
  plaintext_value = cloudflare_api_token.workload[each.key].value
}
