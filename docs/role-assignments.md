# Role Assignments Reference

Audience: senior engineers designing or reviewing workload configuration.

## Shapes and Levels

### Environment level

```json
{
  "role_assignments": {
    "assigned_roles": [
      { "roles": ["Contributor", "User Access Administrator"] },
      { "scope": "/subscriptions/.../resourceGroups/rg-x", "roles": ["DNS Zone Contributor"] }
    ],
    "rbac_admin_roles": [
      { "allowed_roles": ["Key Vault Secrets Officer"] },
      { "scope": "sub-other", "allowed_roles": ["Storage Blob Data Contributor"] }
    ]
  }
}
```

- If `scope` is omitted, the environment subscription alias is used.
- `assigned_roles` are expanded into Azure role assignments for the workload service principal; when `add_deploy_script_identity=true`, the deploy script UAI receives the same set.
- A `Reader` assignment is auto-added at the environment subscription scope; if an entry uses the environment subscription alias or omits its scope, `Reader` is merged into its roles.
- Scopes accept subscription aliases, raw ARM IDs and workload helpers; see
  [scope input options](workload-configuration.md#role-assignments).
- `rbac_admin_roles` grant `Role Based Access Control Administrator` on the resolved scope with a condition limiting which role definitions can be written/deleted (the `allowed_roles`).
- Workload JSON uses the stable symbolic identifier `Workload Key Vault Secret
  Synchronizer`. Terraform resolves that identifier at the target RBAC scope
  to the subscription-local Azure role named `Workload Key Vault Secret
  Synchronizer <subscription-prefix>`. Each role permits only
  `Microsoft.KeyVault/vaults/secrets/setSecret/action`, allowing secret
  synchronization without read, list, delete, recover, or purge access.
- Bare-metal workload vaults delegate `Key Vault Secrets User` so the
  platform deployment can assign vault read access to the hosting Arc
  machine's managed identity. This is a Key Vault data-plane assignment; it
  does not require `Azure Connected Machine Resource Metadata Reader`.

### Resource-group level

```json
{
  "resource_groups": [
    {
      "name": "rg-{workload}-{env}-{location}",
      "role_assignments": {
        "assigned_roles": [
          { "roles": ["Contributor"] },
          { "scope": "/subscriptions/.../resourceGroups/rg-other", "roles": ["Reader"] }
        ],
        "rbac_admin_roles": [
          { "allowed_roles": ["Storage Blob Data Contributor"] }
        ]
      }
    }
  ]
}
```

- If `scope` is omitted for a resource group role assignment, the resource group ID is used.
- `assigned_roles` apply to the workload service principal, not the deploy UAI.
- `rbac_admin_roles` apply to the workload service principal, scoped to the RG (or override).
- An explicit raw ARM ID in `assigned_roles` must start with `/subscriptions/`.
  Conditional `rbac_admin_roles` also accept other raw ARM IDs starting with `/`.

## Resolution Rules (Terraform implementation)

- Environment defaults: `scope = coalesce(entry.scope, subscription)`.
- RG defaults: `scope = coalesce(entry.scope, <resource group id>)`.
- Assignment scope: environment uses subscription when scope omitted; RG uses its own ID when scope omitted.
- Subscription alias scopes convert to subscription IDs; supported ARM IDs pass through.
- Reader auto-add compares the declared scope with the environment subscription alias; equivalent scopes written differently do not merge.
- Environment `assigned_roles` target the workload service principal and, when enabled, the deploy script UAI. Resource-group `assigned_roles` and all `rbac_admin_roles` target only the workload service principal.
- RBAC admin: single `Role Based Access Control Administrator` assignment per entry with condition restricting allowed role GUIDs; roles resolved via `data.azurerm_role_definition`.

## Practical Guidance

- Omit each entry's `scope` to use its environment subscription or containing resource group; set a scope on individual entries for exceptions.
- Keep `allowed_roles` minimal; every entry emits a conditional RBAC admin assignment granting delegated rights to manage only those roles.
- Validate aliases in `tfvars` before use; a bad alias breaks scope resolution at plan time.

## Entity Relationships

```mermaid
graph TD
  W[Workload JSON] --> E[Environment]
  E --> RA[Environment role_assignments]
  RA --> AR["assigned_roles (roles, optional scope)"]
  RA --> RB["rbac_admin_roles (allowed_roles, optional scope)"]
  AR -->|expands| RAE["Role assignments to Service Principal"]
  AR -->|if deploy UAI| RAD["Role assignments to Deploy UAI"]
  RAE --> SCOPE1["Resolved scope (alias to subscription ID or ARM ID)"]
  RAD --> SCOPE1
  RB -->|one per entry| RBA["RBAC Admin assignment"]
  RBA -->|condition limits| ALLOWED["Allowed role GUIDs"]

  E --> RG[Resource groups]
  RG --> RRA[RG role_assignments]
  RRA --> RAR[assigned_roles]
  RRA --> RRB[rbac_admin_roles]
  RAR -->|expands| RGRA["RG role assignments to SP"]
  RGRA --> SCOPE2["Resolved scope (override or RG ID when scope omitted)"]
  RRB -->|one per entry| RGRBA["RG RBAC Admin assignment"]
  RGRBA -->|condition limits| ALLOWED
```

# Review Notes (current implementation)

- Reader auto-add is implemented in `local.workload_environments`; resource-group locals do not add it.
- RBAC admin assignments use conditional `Role Based Access Control Administrator` and resolve allowed roles via `azurerm_role_definition` for both env and RG levels.
- Resource group role assignments now use a keyed map to avoid list indexing errors when resolving scopes.
- Environment-level assigned roles also go to the deploy script identity only when `add_deploy_script_identity` is enabled.
