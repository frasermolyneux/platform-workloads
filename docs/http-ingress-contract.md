# HTTP ingress contract

The [catalog](../terraform/ingress/catalog.json) is the non-secret declaration
for the managed baremetal HTTP migration. Version 1 separates **current**
observations from **target** intent. Publishing it does not change DNS,
redirects, firewall rules, maintenance, private access, or applications.
Consumers must not treat a target projection as an instruction to cut over.
Non-baremetal maintenance entries and the maintenance canary remain with their
current owner; Pelican is delegated and excluded.

## Consumption

Consumers with existing trusted access to the full platform-workloads state can
read `http_ingress_catalog` and `http_ingress_target` as described in the
[output guide](consuming-platform-workloads-outputs.md). State access exposes
the entire snapshot and must not be granted merely to read this contract.
Other consumers can check out `terraform/ingress/catalog.json` from a pinned
platform-workloads Git commit using their existing source-distribution tooling.
Record that commit alongside the rendered configuration; do not fetch the
catalog on individual requests. Use the same commit for all projections.

`http_ingress_catalog` is the checked-in JSON. `http_ingress_target.hosts` is
the complete host object keyed by exact lowercase hostname.
`http_ingress_target.version`, `redirect_policy`, and `proxied_origin_access`
repeat the catalog's version and target-wide policy.
`http_ingress_target.maintenance` is keyed by canonical target hostname with
`zone` and `site`; merge it only with the existing canary and non-migrated
entries when their owner implements the migration. `http_ingress_target.private_dns`
maps opted-in exact hostnames to the Tailscale address of the route's `server`.
For Git-based consumers, these projections are the corresponding filters over
`hosts`: select `target.status_brand != null` for maintenance and
`target.private == true` for private DNS and resolve its server through
`private_dns.servers`. These values are also the two `private_dns.resolvers`.
Preserve TTL 0 and identity authorization. Restricted
domains are a separate Tailscale-owned concern; do not infer that unrelated DNS
entries or policy may be removed.

`redirect_policy` requires preserving both path and query for hostname
redirects. `proxied_origin_access` is the target Cloudflare-only public-origin
policy; it does not assert that the current firewall already enforces it.
Each host has `hostname`, `workload`, Cloudflare `zone`, `route` and separate
`current` and `target` objects. `route.server`, `route.profile`, and
`route.upstream` identify the existing host-level rendering destination, not
secret values. `xi-forums` routes terminate at the existing XI private proxy;
its application repository continues to own the path routing and security
checks. `status-origin` is served on both hosts and retains its load balancer,
health checks and failover. `edge-alias` has no new origin. Host-specific
certificates, secret values, application authentication and configuration
remain with their existing owners.

`current.public_mode` is `proxied`, `dns-only`, `tailscale-address`, or null
when not established from the reviewed source. `current.status` records
membership in the existing maintenance allowlist, including aliases;
`current.private` records an existing private route. These observations are
not proof that deployed configuration or clients are healthy.
`target.public_mode` is `proxied`, `dns-only`, or `private-only`;
`target.alias_to` is null for a canonical host or the exact canonical hostname;
`target.https_redirect` declares the desired public HTTP-to-HTTPS behavior;
`target.status_brand` is `mx`, `xi`, or null; and `target.private` requests
identity-checked private ingress. Alias redirects must preserve path and query;
private aliases retain the necessary private redirect. `protocol_exceptions`
inventories nonstandard HTTP endpoints without converting them into web routes.

Validation rejects duplicate or malformed names, missing or chained alias
targets, public aliases to private-only hosts, status on aliases or non-proxied
hosts, invalid Tailscale resolver addresses, missing private route metadata,
and changes to the required resolver/TTL/authorization baseline. Catalog
changes must pass the module's Terraform contract tests. A schema-breaking
change requires a version change and coordinated consumer migration.

## Baseline and handoff

Source observations are pinned here for traceability, not asserted as live
deployment evidence:

- [Baremetal inventory at 294c8a9](https://github.com/frasermolyneux/platform-baremetal/tree/294c8a9cad773fe3976eec3120f3822573e0f36a/ansible/inventories/production)
  supplies route upstreams, WordPress canonical/alias mappings and the two
  private hosts. WordPress origin aliases redirect to their canonical host with
  the URI; private ingress uses identity authorization. The current XI private
  routes include test, www, CDN, maps and redirect.
- [Connectivity at 18517e1](https://github.com/frasermolyneux/platform-connectivity/tree/18517e15ca00a554b9defbc5f9ce581d6c382ff7/terraform/zones)
  declares WordPress and XI proxied records, DNS-only IDP/Radar, and a public
  test record pointing at its Tailscale address. Trip zone record lists are
  empty, so their currently deployed proxy status is deliberately unknown in
  the catalog. On 2026-11-22 ordinary A lookups returned Cloudflare addresses
  for both Trip apex/www pairs, the declared direct origin for IDP and Radar,
  and the Tailscale address for XI test; this is not an authenticated
  Cloudflare record or deployment inspection.
  The XI apex has an enabled Cloudflare redirect to www preserving query;
  its record still points at the legacy origin. Do not remove that dependency
  until the deployed redirect and edge precedence are verified. The
  `molyneux.io` file also contains Azure DNS declarations: their currency has
  not been verified and nothing here authorizes deleting them.
- [Maintenance source at 18517e1](https://github.com/frasermolyneux/platform-connectivity/blob/18517e15ca00a554b9defbc5f9ce581d6c382ff7/maintenance/hosts.json)
  includes aliases as well as canonical hosts. Preserve this current list
  until the consumer parity and cutover waves.
- [Tailscale DNS at 7eff84c](https://github.com/frasermolyneux/platform-tailscale/blob/7eff84c80682b245486824b72a1b48ac0fe19536/terraform/dns.tf)
  uses both resolvers. Tailscale remains the sole policy/DNS writer. Its
  unrelated DNS settings, policy, and exit nodes are outside this contract.
- [XI Caddy at d7a04a3](https://github.com/frasermolyneux/xi-forums/blob/d7a04a3ea8775f73a451e36ff02ee8af18bd0acf/docker/caddy/Caddyfile)
  owns the forum's path-based applications, CDN, maps and functional redirect
  service. Do not substitute a generic hostname redirect for these routes.
- [Status edge at 5b9b348](https://github.com/frasermolyneux/platform-status-web/blob/5b9b3483db02d48c6c0a8b4a76120fab99cf637e/edge/main.tf)
  owns the proxied load balancer and its pool. The HTTPS monitor sends
  `GET /health/ready` with `Host: mxstatus.io`, expects HTTP 200 and a ready
  response, and does not follow redirects. Preserve both origins and this
  probe when changing firewall or ingress behavior.

IDP and Radar retain application authentication, OAuth and service integrations;
Radar's collector calls IDP. Verify their deployed callbacks and integration
paths before any edge or maintenance cutover. Verify live DNS, public and
private routing, certificates, status load-balancer probes, and TeamSpeak
WebQuery consumers without collecting credentials before downstream changes.
TeamSpeak port/access remains unchanged; consumer use has not been established.
Test's public Tailscale-address record must remain until private DNS and
certificate-renewal independence are proven. XI forums and Bishops Bees,
including staging, remain unchanged through the final workload wave.
