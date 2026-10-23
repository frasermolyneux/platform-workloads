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
          secret_name      = upper(try(token.secret_name, "CLOUDFLARE_API_KEY"))
          policies         = token.policies
        }
      ]
    ]
  ])

  cloudflare_zone_names = toset(flatten([
    for token in local.cloudflare_tokens : [
      for policy in token.policies : try([policy.account_from_zone], policy.zones, [policy.zone])
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

  cloudflare_token_accounts = {
    for token in local.cloudflare_tokens : token.key => toset([
      for zone in flatten([
        for policy in token.policies : try([policy.account_from_zone], policy.zones, [policy.zone])
      ]) : data.cloudflare_zone.lookup[zone].account.id
    ])
  }

  # One entry per workload-environment that has a Cloudflare token (all tokens in
  # an environment share the account); drives the CLOUDFLARE_ACCOUNT_ID variable.
  cloudflare_token_environments = {
    for env_key, tokens in { for t in local.cloudflare_tokens : t.environment_key => t... } :
    env_key => tokens[0]
  }

  # Adopted-zone-key activation sets declared per environment in the workload JSON.
  cloudflare_adopted_zone_key_sets = flatten([
    for workload in local.all_workloads : [
      for environment in try(workload.environments, []) : {
        key               = format("%s-%s", workload.name, environment.name)
        workload_name     = workload.name
        adopted_zone_keys = try(environment.cloudflare_adopted_zone_keys, [])
      }
      if length(try(environment.cloudflare_adopted_zone_keys, [])) > 0
    ]
  ])
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
      resources = jsonencode(can(policy.account_from_zone) ? {
        "com.cloudflare.api.account.${data.cloudflare_zone.lookup[policy.account_from_zone].account.id}" = "*"
        } : {
        for zone in try(policy.zones, [policy.zone]) :
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.lookup[zone].id}" => "*"
      })
    }
  ]

  lifecycle {
    precondition {
      condition = alltrue([
        for policy in each.value.policies :
        can(policy.account_from_zone)
        ? (!can(policy.zone) && !can(policy.zones))
        : (can(policy.zone) != can(policy.zones))
      ])
      error_message = "Each Cloudflare token policy must select exactly one of zone, zones, or account_from_zone."
    }
    precondition {
      condition     = length(local.cloudflare_token_accounts[each.key]) == 1
      error_message = "All policies in a workload Cloudflare token must belong to one account."
    }
  }
}

resource "github_actions_environment_secret" "cloudflare_token" {
  for_each = { for token in local.cloudflare_tokens : token.key => token }

  repository      = github_repository.workload[each.value.workload_name].name
  environment     = github_repository_environment.workload[each.value.environment_key].environment
  secret_name     = each.value.secret_name
  plaintext_value = cloudflare_api_token.workload[each.key].value
  lifecycle {
    precondition {
      condition = length([
        for token in local.cloudflare_tokens : token.key
        if token.environment_key == each.value.environment_key && token.secret_name == each.value.secret_name
      ]) == 1
      error_message = "Cloudflare tokens in one workload environment must use distinct GitHub secret names."
    }
  }
}

resource "github_actions_environment_variable" "cloudflare_account_id" {
  for_each = local.cloudflare_token_environments

  repository    = github_repository.workload[each.value.workload_name].name
  environment   = github_repository_environment.workload[each.value.environment_key].environment
  variable_name = "CLOUDFLARE_ACCOUNT_ID"
  value         = one(local.cloudflare_token_accounts[each.value.key])
}

resource "github_actions_environment_variable" "cloudflare_adopted_zone_keys" {
  for_each = { for set in local.cloudflare_adopted_zone_key_sets : set.key => set }

  repository    = github_repository.workload[each.value.workload_name].name
  environment   = github_repository_environment.workload[each.value.key].environment
  variable_name = "CLOUDFLARE_ADOPTED_ZONE_KEYS"
  value         = jsonencode(each.value.adopted_zone_keys)
}
