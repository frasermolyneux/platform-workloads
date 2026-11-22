variables {
  catalog = jsondecode(file("../../ingress/catalog.json"))
}

run "catalog_and_projections" {
  command = plan

  assert {
    condition = (
      output.catalog.version == 1 &&
      output.target.hosts["tripsidekick.app"].target.alias_to == null &&
      output.target.hosts["tripsidekick.net"].target.alias_to == null &&
      output.target.hosts["staging.bishopsbees.co.uk"].target.alias_to == null &&
      output.target.hosts["dm-electricalservices.co.uk"].target.alias_to == "www.dm-electricalservices.co.uk" &&
      !contains(keys(output.target.maintenance), "www.bishopsbees.co.uk") &&
      output.target.maintenance["www.xtremeidiots.com"].site == "xi" &&
      output.target.private_dns["test.xtremeidiots.com"] == "100.87.229.111" &&
      output.target.private_dns["radar.molyneux.io"] == "100.94.115.109" &&
      !contains(keys(output.target.private_dns), "mxstatus.io") &&
      output.target.hosts["test.xtremeidiots.com"].current.public_mode == "tailscale-address" &&
      output.target.hosts["test.xtremeidiots.com"].target.public_mode == "private-only" &&
      output.target.hosts["www.bishopsbees.co.uk"].current.status &&
      output.target.hosts["xtremeidiots.com"].target.alias_to == "www.xtremeidiots.com" &&
      output.catalog.protocol_exceptions[0].hostname == "ts.xtremeidiots.com" &&
      output.catalog.protocol_exceptions[0].port == 10080
    )
    error_message = "The target projection must retain independent canonical services, omit status aliases, and route private hosts to their correct server."
  }
}

run "reject_duplicate_hostname" {
  command = plan
  variables {
    catalog = merge(var.catalog, { hosts = concat(var.catalog.hosts, [var.catalog.hosts[0]]) })
  }
  expect_failures = [terraform_data.contract]
}

run "reject_missing_alias_target" {
  command = plan
  variables {
    catalog = merge(var.catalog, {
      hosts = [for h in var.catalog.hosts : h.hostname == "www.bqba.co.uk" ? merge(h, { target = merge(h.target, { alias_to = "missing.bqba.co.uk" }) }) : h]
    })
  }
  expect_failures = [terraform_data.contract]
}

run "reject_alias_loop" {
  command = plan
  variables {
    catalog = merge(var.catalog, {
      hosts = [for h in var.catalog.hosts : h.hostname == "bqba.co.uk" ? merge(h, { target = merge(h.target, { alias_to = "www.bqba.co.uk", status_brand = null }) }) : h]
    })
  }
  expect_failures = [terraform_data.contract]
}

run "reject_unproxied_status" {
  command = plan
  variables {
    catalog = merge(var.catalog, {
      hosts = [for h in var.catalog.hosts : h.hostname == "bqba.co.uk" ? merge(h, { target = merge(h.target, { public_mode = "dns-only" }) }) : h]
    })
  }
  expect_failures = [terraform_data.contract]
}

run "reject_alias_status" {
  command = plan
  variables {
    catalog = merge(var.catalog, {
      hosts = [for h in var.catalog.hosts : h.hostname == "www.bqba.co.uk" ? merge(h, { target = merge(h.target, { status_brand = "mx" }) }) : h]
    })
  }
  expect_failures = [terraform_data.contract]
}

run "reject_missing_private_route" {
  command = plan
  variables {
    catalog = merge(var.catalog, {
      hosts = [for h in var.catalog.hosts : h.hostname == "radar.molyneux.io" ? merge(h, { route = merge(h.route, { upstream = "" }) }) : h]
    })
  }
  expect_failures = [terraform_data.contract]
}

run "reject_unknown_private_server" {
  command = plan
  variables {
    catalog = merge(var.catalog, {
      hosts = [for h in var.catalog.hosts : h.hostname == "radar.molyneux.io" ? merge(h, { route = merge(h.route, { server = "ns512615" }) }) : h]
    })
  }
  expect_failures = [terraform_data.contract]
}

run "reject_invalid_resolver_address" {
  command = plan
  variables {
    catalog = merge(var.catalog, {
      private_dns = merge(var.catalog.private_dns, {
        resolvers = ["not-an-ip", "100.87.229.111"]
        servers   = merge(var.catalog.private_dns.servers, { ns346663 = "not-an-ip" })
      })
    })
  }
  expect_failures = [terraform_data.contract]
}

run "reject_long_hostname_label" {
  command = plan
  variables {
    catalog = merge(var.catalog, {
      hosts = [for h in var.catalog.hosts : h.hostname == "radar.molyneux.io" ? merge(h, { hostname = "${join("", [for i in range(64) : "a"])}.molyneux.io" }) : h]
    })
  }
  expect_failures = [terraform_data.contract]
}

run "reject_long_hostname" {
  command = plan
  variables {
    catalog = merge(var.catalog, {
      hosts = [for h in var.catalog.hosts : h.hostname == "radar.molyneux.io" ? merge(h, { hostname = "${join(".", [for i in range(4) : join("", [for j in range(63) : "a"])])}.molyneux.io" }) : h]
    })
  }
  expect_failures = [terraform_data.contract]
}

run "reject_public_alias_to_private_host" {
  command = plan
  variables {
    catalog = merge(var.catalog, {
      hosts = [for h in var.catalog.hosts : h.hostname == "bqba.co.uk" ? merge(h, { target = merge(h.target, { public_mode = "private-only", status_brand = null }) }) : h]
    })
  }
  expect_failures = [terraform_data.contract]
}

run "reject_redirect_query_loss" {
  command = plan
  variables {
    catalog = merge(var.catalog, { redirect_policy = merge(var.catalog.redirect_policy, { preserve_query = false }) })
  }
  expect_failures = [terraform_data.contract]
}
