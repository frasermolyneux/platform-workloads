variable "catalog" {
  description = "Ingress catalog override for contract tests; production reads the checked-in JSON."
  type        = any
  default     = null
}

locals {
  catalog            = jsondecode(var.catalog == null ? file("${path.module}/../../ingress/catalog.json") : jsonencode(var.catalog))
  hostnames          = [for host in local.catalog.hosts : host.hostname]
  maintenance_bypass = local.catalog.maintenance_path_policy.bypass
  hosts_by_name = {
    for host in local.catalog.hosts : host.hostname => host...
  }
  servers = local.catalog.private_dns.servers
}

resource "terraform_data" "contract" {
  input = sha256(jsonencode(local.catalog))

  lifecycle {
    precondition {
      condition = try(
        local.catalog.version == 1 &&
        local.catalog.redirect_policy.preserve_path == true &&
        local.catalog.redirect_policy.preserve_query == true &&
        local.catalog.proxied_origin_access == "cloudflare-only" &&
        local.catalog.maintenance_path_policy.when_enabled == "apply-except-listed-paths" &&
        length(local.maintenance_bypass) > 0 &&
        length(distinct([for rule in local.maintenance_bypass :
          jsonencode([rule.hostname, rule.path, rule.match, rule.methods])
        ])) == length(local.maintenance_bypass) &&
        alltrue([for rule in local.maintenance_bypass :
          contains(["idp.molyneux.io", "radar.molyneux.io"], rule.hostname) &&
          contains(local.hostnames, rule.hostname) &&
          startswith(rule.path, "/") &&
          !strcontains(rule.path, "?") &&
          !strcontains(rule.path, "#") &&
          contains(["exact", "prefix"], rule.match) &&
          (rule.match != "prefix" || endswith(rule.path, "/")) &&
          length(rule.methods) > 0 &&
          length(distinct(rule.methods)) == length(rule.methods) &&
          alltrue([for method in rule.methods : contains(["GET", "POST", "PUT", "PATCH", "DELETE"], method)]) &&
          contains(["oauth-callback", "authenticated-service-api"], rule.purpose) &&
          length(trimspace(rule.authentication)) > 0
        ]) &&
        toset(keys(local.servers)) == toset(["ns346663", "ns5019527"]) &&
        length(distinct(values(local.servers))) == 2 &&
        alltrue([for address in values(local.servers) :
          can(regex("^100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.[0-9]{1,3}\\.[0-9]{1,3}$", address)) &&
          can(cidrhost("${address}/32", 0))
        ]) &&
        toset(local.catalog.private_dns.resolvers) == toset(values(local.servers)) &&
        local.catalog.private_dns.ttl == 0 &&
        local.catalog.private_dns.authorization == "tailscale-identity" &&
        length(local.catalog.hosts) > 0 &&
        length(distinct(local.hostnames)) == length(local.hostnames) &&
        alltrue([for host in local.catalog.hosts :
          can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", host.hostname)) &&
          length(host.hostname) <= 253 &&
          alltrue([for label in split(".", host.hostname) : length(label) <= 63]) &&
          (host.hostname == host.zone || endswith(host.hostname, ".${host.zone}")) &&
          length(trimspace(host.workload)) > 0 &&
          contains(["proxied", "dns-only", "private-only"], host.target.public_mode) &&
          contains(["wordpress", "shared", "xi-forums", "xi-test", "edge-alias", "status-origin"], host.route.profile) &&
          (host.current.public_mode == null ? true : contains(["proxied", "dns-only", "tailscale-address"], host.current.public_mode)) &&
          contains([true, false], host.current.status) &&
          contains([true, false], host.current.private) &&
          contains([true, false], host.target.https_redirect) &&
          contains([true, false], host.target.private) &&
          (try(host.target.remove_public_dns_record, false) == false ||
            (host.hostname == "test.xtremeidiots.com" &&
              host.target.remove_public_dns_record == true &&
              host.target.public_mode == "private-only" &&
              host.target.private &&
          host.target.status_brand == null)) &&
          (host.hostname == "test.xtremeidiots.com" ?
            try(host.target.remove_public_dns_record == true, false) :
          try(host.target.remove_public_dns_record != true, true)) &&
          (contains(["idp.molyneux.io", "radar.molyneux.io"], host.hostname) ? try(
            host.target.private &&
            host.target.public_mode == "proxied" &&
            host.target.status_brand == "mx" &&
            host.target.private_ingress.server == host.route.server &&
            host.target.private_ingress.profile == host.route.profile &&
            host.target.private_ingress.proxy == "platform-caddy" &&
            host.target.private_ingress.network == "platform-ingress" &&
            host.target.private_ingress.listener.bind == "tailscale" &&
            host.target.private_ingress.listener.routing == "hostname" &&
            host.target.private_ingress.listener.port == 443 &&
            host.target.private_ingress.upstream == host.route.upstream &&
            host.target.private_ingress.trusted_proxy.proxy == host.target.private_ingress.proxy &&
            host.target.private_ingress.trusted_proxy.network == host.target.private_ingress.network,
            false
          ) : try(host.target.private_ingress == null, true)) &&
          (host.target.status_brand == null ? true : (
            contains(["mx", "xi"], host.target.status_brand) &&
            host.target.public_mode == "proxied" && host.target.alias_to == null
          )) &&
          (host.target.private ? (
            contains(["ns346663", "ns5019527"], host.route.server) &&
            length(trimspace(host.route.upstream)) > 0 &&
            length(trimspace(host.route.profile)) > 0
          ) : host.target.public_mode != "private-only") &&
          (host.target.alias_to == null ? true : try(
            host.target.alias_to != host.hostname &&
            length(local.hosts_by_name[host.target.alias_to]) == 1 &&
            local.hosts_by_name[host.target.alias_to][0].target.alias_to == null &&
            local.hosts_by_name[host.target.alias_to][0].workload == host.workload &&
            (host.target.public_mode == "private-only" || local.hosts_by_name[host.target.alias_to][0].target.public_mode != "private-only") &&
            (!host.target.private || local.hosts_by_name[host.target.alias_to][0].target.private),
            false
          ))
        ]),
        false
      )
      error_message = "Ingress requires unique valid hostnames, canonical alias targets, proxied canonical status hosts, and an identified server, profile and upstream for every private route."
    }
  }
}

output "catalog" {
  description = "Versioned non-secret ingress declaration; current observations and target intent are distinct."
  value       = local.catalog
  depends_on  = [terraform_data.contract]
}

output "target" {
  description = "Deterministic target projections. Consumers choose when to activate them."
  value = {
    version                 = local.catalog.version
    redirect_policy         = local.catalog.redirect_policy
    proxied_origin_access   = local.catalog.proxied_origin_access
    maintenance_path_policy = local.catalog.maintenance_path_policy
    hosts                   = { for host in local.catalog.hosts : host.hostname => host }
    maintenance = {
      for host in local.catalog.hosts : host.hostname => {
        zone = host.zone
        site = host.target.status_brand
      } if host.target.status_brand != null
    }
    private_dns = {
      for host in local.catalog.hosts : host.hostname => lookup(local.servers, host.route.server, null)
      if host.target.private
    }
    private_routes = {
      for host in local.catalog.hosts : host.hostname => merge(host.target.private_ingress, {
        hostname = host.hostname
        workload = host.workload
      }) if try(host.target.private_ingress != null, false)
    }
    public_record_removals = sort([
      for host in local.catalog.hosts : host.hostname
      if try(host.target.remove_public_dns_record, false)
    ])
  }
  depends_on = [terraform_data.contract]
}
