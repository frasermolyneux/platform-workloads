# IDP host collector cutover

## Ownership and identity contract

`platform-workloads` remains authoritative for the existing shared GitHub App
key and its rotation/distribution. The source is `github-app-pem` in
`kv-07959418ca04-uksouth`, in `rg-platform-workloads-prd-uksouth-01`,
subscription `7760848c-794d-4a19-8cb2-52f71a21ac2b`. Existing Actions
distribution is unchanged. Do not create another App, key, or copied secret.
The existing secret value remains externally populated, with Terraform ignoring
value changes; this cutover neither generates nor rotates it.

The confirmed worker host is `ns346663`, the Production IDP host in
`platform-baremetal`. Its Arc resource is:

```text
/subscriptions/7760848c-794d-4a19-8cb2-52f71a21ac2b/resourceGroups/rg-platform-baremetal-prd-uksouth/providers/Microsoft.HybridCompute/machines/ns346663
```

Read-only ARM inspection confirmed system-assigned principal
`cecfaca8-1076-4439-8b0e-7da8b82c2600`, tenant
`e56a6947-bb9a-4a6e-846a-1f118d1c3a14`. These are verification metadata,
not copied principal configuration: Terraform resolves the host through ARM at
plan time, anchored to the existing baremetal Production catalog resource group.
The lookup fails if its subscription differs from the provider subscription or
its system identity is absent/foreign. No reverse baremetal remote-state read is
introduced: baremetal already consumes this stack's outputs.

The only new permission is **Key Vault Secrets User** on the exact ARM scope
`<central-vault-id>/secrets/github-app-pem` (versionless). There is no vault-wide
Reader, secret listing, writer, or role-administration grant. New versions use
the same scope. The host's established Arc external-secrets mechanism hydrates
`collector-github-app.pem` in the IDP configuration root, outside the portal's
mounted secret subtree; only the worker mounts it. The host is the trusted
hydration boundary, not the container's Azure authentication mechanism.

The collector itself uses certificate authentication to IDP's existing
`azuread_application.collector` / `azuread_service_principal.collector`.
IDP renames it to `MX.IO IDP host collector (prd)`, removes CI federation,
and preserves its client ID, principal ID, and Production
`IDP_COLLECTOR_CLIENT_ID` publication. The existing independently checked
client-ID/display-name resolution stays in place without reverse IDP state.
`platform-workloads` retains **Cost Management Reader** on exactly the distinct
subscription scopes selected by the existing budget-policy contract; budgets,
workload declarations and role-assignment addresses are unchanged.
The worker retains its narrowly scoped Collector API role and client allowlist
for claiming/submitting work through authenticated IDP endpoints; it does not
mount the portal's production SQLite database.

The collector certificate `idp-collector` and runtime-vault access are owned by
IDP/host integration, not this central shared-key grant. The portal runtime vault
is in a different subscription; do not use its ID as the central vault or assume
baremetal's scoped RBAC delegation covers the central vault. This stack's existing
Production deployment principal must perform the central secret grant.

## Production deployment

Deploy Prd uses the repository's standard shared Terraform plan-and-apply action.
PR Verify and Feature Development use the standard shared Terraform plan action.
The temporary IDP-specific release runner, diagnostics and retirement preflight
have been removed. The shared actions retain their existing state concurrency,
OIDC authentication and Terraform execution receipts.

The central secret grant was deployed by
[Deploy Prd run 42913550135](https://github.com/frasermolyneux/platform-workloads/actions/runs/42913550135)
at `ea3160a3466ecb5d8a5bb5761f96372be0ac9fa3`. Read-only Azure verification
confirmed assignment `10cca3c3-19bb-42b3-ffba-e4e9cd076f7c`, the host principal
above and the exact versionless secret scope. Host hydration and application
deployment do not depend on removal of the temporary runner.

For future identity changes, preserve the existing collector client/principal,
cost-reader scopes and budget declarations. The host must hydrate the shared
key through its existing external-secrets mechanism, with restrictive ownership
and a worker-only mount. Verify GitHub App authentication and Azure cost
collection without logging credentials or mounting the portal database.

## Local validation

Select the exact CLI from `terraform/.terraform-version`. Mock tests do not read
secrets:

```powershell
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false -lockfile=readonly
terraform -chdir=terraform validate
terraform -chdir=terraform test '-var-file=tfvars\prd.tfvars' '-filter=tests\idp-cost-reader.tftest.hcl' '-filter=tests\idp-collector-host.tftest.hcl'
```

Verify role-assignment metadata at the exact secret ARM scope for the Arc
principal, and retained Cost Management Reader assignments for the collector
principal at all policy subscription scopes. The host hydration service provides
data-plane verification and must not emit key material.
