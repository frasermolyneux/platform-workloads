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

## Coordinated production sequence

1. Land and deploy IDP's identity/certificate Terraform changes first, preserving
   the existing collector client/principal and variable publication. This
   identity/bootstrap preparation retires CI collection and its federation first;
   the temporary collection outage until host-worker activation is accepted.
   Confirm the exact new display name in Entra before planning this stack. The
   host worker remains stopped until permissions, certificate and shared-key
   hydration are ready.
2. Select the exact CLI from `terraform/.terraform-version` (`1.17.0`). Run the
   credential-free checks below in this worktree. Mock tests do not read secrets.
3. In the secured Production deployment context, initialize and review a complete
   state-backed plan. Do not run a targeted production plan/apply. Normal full
   stack refresh reads existing broker secrets; never print state, secret values
   or plan JSON, and do not download secret-bearing state to inspect this change.
   Expect one new secret-scoped assignment and no change to the cost-reader
   principals/scopes, budgets, unrelated workloads or shared key. Stop on any
   unexpected change. The Arc machine must already exist, and deployment needs
   ARM read access to it plus role-assignment authority at the central secret.
4. After coordinated approval/landing on `main`, use the existing **Deploy Prd**
   workflow (`.github/workflows/deploy-prd.yml`), which performs the complete
   Production plan/apply on push or dispatch. Do not apply locally or create a
   duplicate manual role assignment. Do not interrupt a running stateful deployment.
5. After RBAC propagation, deploy the host external-secrets binding and worker.
   Verify host-side hydration succeeds without logging its contents, restrictive
   file ownership/mode and worker-only mount, then verify GitHub App installation
   authentication and one Azure cost collection with the preserved collector SP.
   Confirm collection freshness in IDP to close the accepted collection outage;
   CI collection and federation were already retired in step 1. Any rollback
   restoring CI collection or federation belongs to the IDP stack and requires
   coordination; do not recreate or move the cost role assignments or alter budgets.

```powershell
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false -lockfile=readonly
terraform -chdir=terraform validate
terraform -chdir=terraform test '-var-file=tfvars\prd.tfvars' '-filter=tests\idp-cost-reader.tftest.hcl' '-filter=tests\idp-collector-host.tftest.hcl'
```

Secured Production plan prerequisites/commands (not executed by this worktree):

```powershell
terraform -chdir=terraform init -lockfile=readonly -reconfigure -backend-config=backends/prd.backend.hcl
terraform -chdir=terraform plan -var-file=tfvars/prd.tfvars
```

Verify the role-assignment metadata at the exact secret ARM scope for the
resolved Arc principal, and retained Cost Management Reader assignments for the
collector principal at all policy subscription scopes. Inspect metadata only;
do not use a secret-get command as a verification probe. The host hydration
service is the authorized data-plane verification and must not emit key material.
