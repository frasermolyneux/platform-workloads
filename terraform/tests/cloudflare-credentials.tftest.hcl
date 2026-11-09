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
    condition = try(one([
      for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
      if token.name_suffix == "dns"
    ]).secret_name, "CLOUDFLARE_API_KEY") == "CLOUDFLARE_API_KEY"
    error_message = "The connectivity Production DNS token must populate the CLOUDFLARE_API_KEY environment secret."
  }

  assert {
    condition = length(one([
      for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
      if token.name_suffix == "dns"
      ]).policies) == 2 && length([
      for policy in one([
        for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
        if token.name_suffix == "dns"
      ]).policies : policy
      if can(policy.zones)
      ]) == 1 && toset(one([
        for policy in one([
          for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
          if token.name_suffix == "dns"
        ]).policies : policy if can(policy.zones)
    ]).permission_groups) == toset(["DNS Write", "Cache Settings Write", "Config Settings Write", "Dynamic URL Redirects Write", "Page Rules Write", "Zone Read", "Zone Settings Write", "Zone WAF Write", "Zone Write"])
    error_message = "The connectivity Production DNS token must grant its zone management permissions consistently in one zone policy."
  }

  assert {
    condition = one([
      for policy in one([
        for token in one([for env in jsondecode(file("${path.module}/workloads/platform/platform-connectivity.json")).environments : env if env.name == "Production"]).cloudflare_tokens : token
        if token.name_suffix == "dns"
      ]).policies : policy if can(policy.account_from_zone)
      ]) == {
      permission_groups = ["Workers Scripts Write"]
      account_from_zone = "xtremeidiots.com"
    }
    error_message = "The connectivity Production DNS token must preserve its existing Workers Scripts account policy."
  }
}
