variable "catalog" {
  description = "Ingress catalog override for contract tests; production reads the checked-in JSON."
  type        = any
  default     = null
}

locals {
  catalog   = var.catalog == null ? jsondecode(file("${path.module}/../../ingress/catalog.json")) : var.catalog
  hostnames = [for host in local.catalog.hosts : host.hostname]
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
    version               = local.catalog.version
    redirect_policy       = local.catalog.redirect_policy
    proxied_origin_access = local.catalog.proxied_origin_access
    hosts                 = { for host in local.catalog.hosts : host.hostname => host }
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
  }
  depends_on = [terraform_data.contract]
}
