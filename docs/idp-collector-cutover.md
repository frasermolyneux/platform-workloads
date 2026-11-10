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
4. After coordinated approval/landing on `main`, use **Deploy Prd**
   (`.github/workflows/deploy-prd.yml`). Its push, dispatch and scheduled triggers
   all enforce the release-specific saved-plan policy below. Do not apply locally
   or create a duplicate manual role assignment. Do not interrupt a running
   stateful deployment.
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

For this release, use the guarded hosted plan-only check rather than manually
executing the illustrative plan commands above. Keep any PR in draft until the
identity rename is deployed and the coordinator clears the plan gate.

## Temporary release restriction

`scripts/guard_idp_cutover.py` replaces the combined shared plan/apply action for
this release. Every **Deploy Prd** trigger runs the same policy. It initializes
with the committed provider lock read-only and the exact root CLI, validates,
then makes a complete refreshed, state-locked Production plan. CLI argument
injection and non-default workspaces are rejected. There are no targets,
refresh suppression or provider changes.

The runner privately converts that saved binary plan to JSON. It requires a
complete, error-free Terraform 1.17.0 plan and rejects deferred changes,
non-passing checks, drift, moves, imports, action invocations and output changes.
The only allowed managed change is one create at
`azurerm_role_assignment.idp_collector_github_app_reader`, with the exact live
principal, role, principal type and versionless central-secret scope documented
above. Unknown principal/scope/role, additional grants, updates, deletes and
replacements block deployment. Existing managed resources and outputs must be
no-op. A genuinely empty repeat plan succeeds without applying anything.

Only AzureRM 5.10.0's narrowly enumerated computed unknowns are accepted for the
new assignment: `id`, `name`, `role_definition_id`, `condition_version` and
`skip_service_principal_aad_check`. Principal, scope, principal type and
`role_definition_name` must be known and exact. A known role-definition ID must
match the built-in Secrets User role. A computed condition version is accepted
only while the condition itself is known null. A mock-provider integration test
generates the actual locked provider's resource-change shape; this is not a
production-plan fixture or a copy of secret-bearing state.

On acceptance, the same saved binary, checked for unchanged SHA-256 after
inspection, is passed to `terraform apply`; no replan is performed. Terraform's
stale-plan/state-serial checks still apply. Other state writers must remain
coordinated: state locking does not span the gap between plan and apply and does
not prevent out-of-band infrastructure changes. A failure requires a new complete
plan and policy check, never a bypass or targeted apply.

Terraform stdout/stderr (including errors), saved plan, JSON and state are never
printed, uploaded, posted to PRs or handed to another job. Private temporary files
are removed on normal success or failure; interrupted hosted runners are
ephemeral. Logs contain only fixed, nonsecret policy/execution summaries. A
failure deliberately does not echo provider diagnostics or rejected plan values.
Do not enable Terraform debug logging, add artifact uploads or print private files
to diagnose it. Investigation of a blocked plan belongs in a separately approved
secured context, without exposing raw plan/state/JSON or secret material.

**PR Verify** preserves the required `terraform-plan-prd` job and its existing
non-draft condition, using this runner with `--plan-only`. **Feature Development**
uses the same private plan-only path. Keep the candidate draft and do not dispatch
either Production plan before the identity rename and coordinator clearance.
The PR check stores no plan outside its temporary runner directory and applies
nothing. Its result proves that its own commit/state snapshot satisfied policy;
it is **not** the plan later applied on `main`. The main run creates a fresh
complete plan and must pass the same policy independently before applying it.
This does not depend on changing Production environment protections.

This is deliberately a **release-scoped restriction**, not a permanent estate
deployment policy. It will block subsequent legitimate infrastructure changes
until explicitly updated or retired. After verified cutover, create a separately
reviewed follow-up to replace/remove the restriction in all three workflow
callers and update/remove its tests and documentation together. A future release
allowlist must identify its exact approved resource actions, scopes and principals
and add positive/negative tests. Never widen to arbitrary changes, catch policy
errors as success, add a bypass input or silently revert to unrestricted fresh
plan/apply to unblock a scheduled deployment. Restoring a general deployment
mechanism is an explicit return to its pre-existing risk profile, not permanent
estate-policy reform; the credential-free test job is not production clearance.

The retirement change must replace the guard invocation in
`.github/workflows/deploy-prd.yml`, `.github/workflows/pr-verify.yml` and
`.github/workflows/feature-development.yml` atomically, preserve the required PR
check and restore the known pre-existing behavior under the hold below. Retain
the release preflight executable through the transition; deliberately retire its
release-only wiring tests when all three callers are replaced, and update the
Build and Test step and this guide in the reviewed change. Current wiring tests
deliberately fail partial removal;
there is no automatic expiration or environment/input escape hatch. A blocked
deployment explicitly names the active restriction and this retirement guide,
and a subprocess test verifies that message remains nonsecret and exits nonzero.
Until a replacement is approved, failing closed is intentional, including for
Feature Development and scheduled runs.

### Executable retirement preflight and operational hold

After host hydration, authenticated collection and unchanged cost scopes have
been verified, the operator can run the tested stricter mode in the secured
Production context with the same OIDC/provider credentials and CLI pin:

```powershell
python scripts/guard_idp_cutover.py --retirement-preflight
```

This makes a new complete refreshed locked plan, permits **only an empty plan**
(even the formerly approved create is rejected), deletes private output, and
never applies or changes the policy. Tests cover empty acceptance, remaining
grant/drift rejection and absence of an apply invocation. It is an executable
transition check, not an unrestricted deployment bypass.

The separately authorized post-cutover retirement procedure is:

1. Wait for every stateful plan/apply to finish. Explicitly hold deployment with
   `gh workflow disable deploy-prd.yml --repo frasermolyneux/platform-workloads`
   **before** landing a retirement workflow change. Do not cancel running jobs.
   Verify the workflow reports `disabled_manually`; hold other state writers too.
   Ensure there are no queued, waiting, pending or in-progress Production writers
   from Deploy Prd, Feature Development or PR Verify before proceeding. Recheck
   immediately before promotion and re-enabling; disabling a workflow is not proof
   that already-admitted jobs have drained. These operational changes are not
   performed by this candidate.
2. Run the retirement preflight on the deployed cutover SHA. Stop on any drift or
   remaining create; do not broaden policy to force retirement.
3. After successful cutover, prepare a one-time retirement commit restoring the
   pre-existing workflow files from the exact pre-guard candidate revision:

   ```powershell
   git restore --source=5443059eb9a9cb8ad1635d265a6ef4940ef96eba -- .github/workflows/deploy-prd.yml .github/workflows/pr-verify.yml .github/workflows/feature-development.yml .github/workflows/build-and-test.yml
   ```

   This is an operator procedure for a new isolated retirement branch, **not**
   a command to run in the current candidate. Review the diff: restore only these
   workflow files, preserve intervening unrelated workflow changes if any, and
   retain the guard executable for preflight until step 5 completes. The restored
   Build and Test still discovers all Python tests, so in the retirement commit
   deliberately remove the release-only test file after running it on the guarded
   revision; it asserts guard wiring and would otherwise reject intentional
   retirement. Keep the executable guard itself through the transition.
4. Land the approved retirement revision while **Deploy Prd is disabled**.
   Editing `deploy-prd.yml` normally matches its own main push trigger; the hold
   prevents this transition from launching an unguarded apply. Check the exact
   landed source SHA and run the still-available preflight in the secured context
   before removing its script, or retain it through a two-commit retirement.
   Require an empty transition plan and passing normal workflow checks. Freeze
   unrelated configuration and out-of-band changes through the transition; if
   anything changes after preflight, repeat it before proceeding.
5. After reconfirming no queued/in-flight writers and recording the empty full
   plan on the retirement SHA, explicitly
   re-enable with `gh workflow enable deploy-prd.yml --repo frasermolyneux/platform-workloads`.
   Do not dispatch a catch-up apply as part of retirement. Enabling does not
   authorize an old plan or prove that a later fresh plan is empty. Remove the
   remaining release script in a follow-up that changes no Terraform or deploy
   workflow files, and update this guide to record completed retirement.

**Restored behavior retains the pre-existing unbounded drift risk:** the shared
combined action makes and automatically applies a fresh full plan, not the
reviewed PR/preflight plan, and prints its human-readable output and stores the
plan as before. The operational hold and empty transition plan prevent a surprise
apply during retirement; they are not a permanent guarantee against drift on
later scheduled, push or manual deployments. No additional permanent estate
deployment policy is introduced by this temporary release guard. Retirement must
be coordinated, and environment protection changes are neither required nor
assumed. This candidate performs none of the hold, restoration or re-enabling.

Verify the role-assignment metadata at the exact secret ARM scope for the
resolved Arc principal, and retained Cost Management Reader assignments for the
collector principal at all policy subscription scopes. Inspect metadata only;
do not use a secret-get command as a verification probe. The host hydration
service is the authorized data-plane verification and must not emit key material.
