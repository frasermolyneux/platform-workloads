## Consuming platform-workloads outputs from remote state

This guide shows how a downstream workload (e.g., platform-sitewatch-func) reads platform-workloads state to reuse resource groups, Terraform backends, and Administrative Units (AU) without re-deriving names. The upstream state exposes three keyed outputs:

- `workload_resource_groups[workload][env_tag]`: resource group objects keyed by location.
- `workload_terraform_backends[workload][env_tag]`: Terraform backend metadata when `configure_for_terraform=true` in the workload JSON.
- `workload_administrative_units[workload][env_tag]`: AU identifiers when the workload has an administrative unit configured.

`env_tag` is the lowercase environment alias from `var.environment_map` (Development → `dev`, Testing → `tst`, Production → `prd`). Always index with the tag, not the display name.

### Remote state wiring (OIDC)

Declare inputs for the platform-workloads backend and workload identity:

```hcl
variable "environment" { type = string }          # dev/tst/prd (tag form)
variable "workload_name" { type = string }       # matches platform-workloads JSON name
variable "locations" { type = list(string) }     # locations you expect to consume

variable "platform_workloads_state" {
  description = "Backend config for the platform-workloads remote state"
  type = object({
    resource_group_name  = string
    storage_account_name = string
    container_name       = string
    key                  = string
    subscription_id      = string
    tenant_id            = string
  })
}

data "terraform_remote_state" "platform_workloads" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.platform_workloads_state.resource_group_name
    storage_account_name = var.platform_workloads_state.storage_account_name
    container_name       = var.platform_workloads_state.container_name
    key                  = var.platform_workloads_state.key
    subscription_id      = var.platform_workloads_state.subscription_id
    tenant_id            = var.platform_workloads_state.tenant_id
    use_oidc             = true
  }
}
```

### Opinionated projection (maps you can reuse)

This pattern keeps each output as a location- or env-tag keyed map so IDs, names, and tags stay available for diagnostics and tagging.

```hcl
locals {
  # Resource groups keyed by location
  workload_rgs = {
    for location in var.locations :
    location => data.terraform_remote_state.platform_workloads.outputs
      .workload_resource_groups[var.workload_name][var.environment]
      .resource_groups[lower(location)]
  }

  # Terraform backend metadata (only present if configure_for_terraform=true upstream)
  workload_backend = try(
    data.terraform_remote_state.platform_workloads.outputs
      .workload_terraform_backends[var.workload_name][var.environment],
    null
  )

  # Administrative Unit identifiers (present when the workload defines an AU)
  workload_au = try(
    data.terraform_remote_state.platform_workloads.outputs
      .workload_administrative_units[var.workload_name][var.environment],
    null
  )
}
```

### Example usage

Use the projected locals directly when creating resources or assigning roles:

```hcl
# Place a Function App per location, merging upstream tags
resource "azurerm_linux_function_app" "app" {
  for_each = local.workload_rgs

  name                = "func-${each.key}-${var.environment}"
  resource_group_name = each.value.name
  location            = each.key
  service_plan_id     = azurerm_service_plan.plan[each.key].id

  tags = merge(each.value.tags, { Component = "sitewatch" })
}

# Consume the upstream Terraform backend (e.g., to let another stack read a sibling state)
locals {
  backend_config = local.workload_backend == null ? {} : {
    resource_group_name  = local.workload_backend.resource_group_name
    storage_account_name = local.workload_backend.storage_account_name
    container_name       = local.workload_backend.container_name
    key                  = local.workload_backend.key
    subscription_id      = local.workload_backend.subscription_id
    tenant_id            = local.workload_backend.tenant_id
  }
}

# Assign an AU-scoped role if available
resource "azuread_directory_role_assignment" "au_reader" {
  count = local.workload_au == null ? 0 : 1

  role_id          = data.azuread_directory_role.reader.id
  principal_object_id = azuread_group.support.object_id
  directory_scope_id  = local.workload_au.administrative_unit_object_id
}
```

### Practices to keep consistent

- Normalize `locations` to lowercase when indexing `resource_groups`.
- Keep `environment` as the tag (`dev`/`tst`/`prd`); the upstream output already carries the full display name separately.
- Prefer `use_oidc=true` instead of storage account keys when reading remote state.
- Reuse upstream tags on downstream resources to keep cost/monitoring views aligned.
- Guard optional outputs (`workload_terraform_backends`, `workload_administrative_units`) with `try(...)` to stay resilient when a workload has not enabled those features.