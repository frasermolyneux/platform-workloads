run "validate_baremetal_cloudflare_credentials" {
  command = plan

  plan_options {
    target = [terraform_data.repository_analysis_contract]
  }

  assert {
    condition = one([
      for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-baremetal.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
      if token.name_suffix == "acme-dns"
    ]).secret_name == "CLOUDFLARE_ACME_DNS_API_TOKEN"
    error_message = "The baremetal ACME DNS token must use its dedicated secret."
  }

  assert {
    condition = one([
      for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-baremetal.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
      if token.name_suffix == "acme-dns"
      ]).policies == [{
      permission_groups = ["DNS Write", "Zone Read"]
      zones             = ["xtremeidiots.com", "xtremeidiots.net", "mxstatus.io"]
    }]
    error_message = "The ACME DNS token must retain its permissions and cover the three required zones."
  }

  assert {
    condition = one([
      for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-baremetal.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
      if token.name_suffix == "maintenance-traffic"
    ]).secret_name == "CLOUDFLARE_MAINTENANCE_TRAFFIC_API_TOKEN"
    error_message = "The baremetal maintenance traffic token must use its dedicated secret."
  }

  assert {
    condition = one([
      for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-baremetal.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
      if token.name_suffix == "maintenance-traffic"
      ]).policies == [
      {
        permission_groups = ["Workers Routes Write", "DNS Read"]
        zones = [
          "bishopsbees.co.uk",
          "bqba.co.uk",
          "buckfastqueen.co.uk",
          "dm-electricalservices.co.uk",
          "moanclub.com",
          "mx-mail.io",
          "queensforsale.co.uk",
          "xtremeidiots.com",
          "xtremeidiots.net"
        ]
      },
      {
        permission_groups = ["Account Analytics Read"]
        account_from_zone = "xtremeidiots.com"
      }
    ]
    error_message = "The maintenance traffic token must retain its zone and account permissions."
  }

  assert {
    condition     = length(one([for env in jsondecode(file("${path.module}/workloads/platform/platform-baremetal.json")).environments : env if env.name == "Production"]).cloudflare_tokens) == 2
    error_message = "The baremetal Production environment must have exactly two Cloudflare tokens."
  }
}

run "validate_connectivity_zone_permissions" {
  command = plan

  plan_options {
    target = [terraform_data.repository_analysis_contract]
  }

  assert {
    condition = upper(try(one([
      for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
      if token.name_suffix == "dns"
    ]).secret_name, "CLOUDFLARE_API_KEY")) == "CLOUDFLARE_API_KEY"
    error_message = "The connectivity Production DNS token must populate the CLOUDFLARE_API_KEY environment secret."
  }

  assert {
    condition = length(one([
      for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
      if token.name_suffix == "dns"
    ]).policies) == 3
    error_message = "The connectivity Production DNS token must have one multi-zone policy, one Bot Management zone policy and one account policy."
  }

  assert {
    condition = length([
      for policy in one([
        for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
        if token.name_suffix == "dns"
      ]).policies : policy if can(policy.zones)
    ]) == 2
    error_message = "The connectivity Production DNS token must have exactly two zone policies."
  }

  assert {
    condition = toset(one([
      for policy in one([
        for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
        if token.name_suffix == "dns"
      ]).policies : policy if try(length(policy.zones), 0) > 1
    ]).permission_groups) == toset(["DNS Write", "Cache Settings Write", "Config Settings Write", "Dynamic URL Redirects Write", "Page Rules Write", "Zone Read", "Zone Settings Write", "Zone WAF Write", "Zone Write"])
    error_message = "The connectivity Production DNS token must grant the required zone permissions consistently."
  }

  assert {
    condition = one([
      for policy in one([
        for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
        if token.name_suffix == "dns"
      ]).policies : policy if try(length(policy.zones), 0) == 1
      ]) == {
      permission_groups = ["Bot Management Read", "Bot Management Write"]
      zones             = ["xtremeidiots.com"]
    }
    error_message = "Bot Management Read and Write must be isolated to xtremeidiots.com on the connectivity Production DNS token."
  }

  assert {
    condition = one([
      for policy in one([
        for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
        if token.name_suffix == "dns"
      ]).policies : policy if can(policy.account_from_zone)
    ]).account_from_zone == "xtremeidiots.com"
    error_message = "The connectivity Production DNS token must preserve its existing account scope."
  }

  assert {
    condition = toset(one([
      for policy in one([
        for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
        if token.name_suffix == "dns"
      ]).policies : policy if can(policy.account_from_zone)
    ]).permission_groups) == toset(["Workers Scripts Write"])
    error_message = "The connectivity Production DNS token must preserve only Workers Scripts Write in its account policy."
  }

  assert {
    condition = toset(one([
      for policy in one([
        for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
        if token.name_suffix == "dns"
      ]).policies : policy if try(length(policy.zones), 0) > 1
      ]).zones) == toset([
      "bishopsbees.co.uk",
      "blogformyparents.co.uk",
      "bqba.co.uk",
      "buckfastqueen.co.uk",
      "craftpledge.org",
      "dm-electricalservices.co.uk",
      "geo-location.net",
      "midlr.com",
      "midlr.co.uk",
      "moanclub.com",
      "molyfra.uk",
      "molyneux-consulting.co.uk",
      "molyneux.dev",
      "molyneux.io",
      "molyneux.me",
      "mx-consulting.co.uk",
      "mx-mail.io",
      "mxstatus.io",
      "osotnoc.co.uk",
      "qrquest.io",
      "queensforsale.co.uk",
      "ratemysteak.co.uk",
      "talkwithtiles.com",
      "tidelife.co.uk",
      "tripsidekick.app",
      "tripsidekick.net",
      "travellingkermit.com",
      "xiredirect.com",
      "xtre.co.uk",
      "xtremeidiots.com",
      "xtremeidiots.dev",
      "xtremeidiots.net"
    ])
    error_message = "The connectivity Production DNS token must cover all catalog zones."
  }
}

run "validate_migrating_workload_dns_permissions" {
  command = plan

  plan_options {
    target = [terraform_data.repository_analysis_contract]
  }

  assert {
    condition = alltrue(flatten([
      for file_path, zone in {
        "workloads/geo-location/geo-location.json" = "geo-location.net"
        "workloads/misc/craftpledge.json"          = "craftpledge.org"
        "workloads/molyneux-me/molyneux-me.json"   = "molyneux.me"
        "workloads/molyneux-me/twenty-one.json"    = "molyneux.me"
        } : [
        for env in ["Development", "Production"] :
        one([for token in one([for e in jsondecode(file("${path.module}/${file_path}")).environments : e if e.name == env]).cloudflare_tokens : token if token.name_suffix == "dns"]) == {
          name_suffix = "dns"
          policies = [{
            permission_groups = ["DNS Write", "Zone Read"]
            zone              = zone
          }]
        }
      ]
    ]))
    error_message = "Each migrating workload environment must have a DNS token scoped to its own zone."
  }

  assert {
    condition = alltrue([
      for file_path, zone in {
        "workloads/geo-location/geo-location.json" = "geo-location.net"
        "workloads/misc/craftpledge.json"          = "craftpledge.org"
        "workloads/molyneux-me/molyneux-me.json"   = "molyneux.me"
        "workloads/molyneux-me/twenty-one.json"    = "molyneux.me"
      } :
      one([for token in one([for e in jsondecode(file("${path.module}/${file_path}")).environments : e if e.name == "Development"]).cloudflare_tokens : token if token.name_suffix == "dependabot-dns"]) == {
        name_suffix     = "dependabot-dns"
        dependabot_only = true
        policies = [{
          permission_groups = ["DNS Read", "Zone Read"]
          zone              = zone
        }]
      }
    ])
    error_message = "Each migrating workload must have a read-only Dependabot token scoped to its own zone."
  }

  assert {
    condition = one([
      for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-notifications.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
      if token.name_suffix == "acs-dns"
      ]).policies == [{
      permission_groups = ["DNS Write", "Zone Read"]
      zones             = ["craftpledge.org", "geo-location.net", "molyneux.dev", "molyneux.io", "molyneux.me", "xtremeidiots.com"]
    }]
    error_message = "The Production ACS token must cover only its sending-domain zones."
  }
}
