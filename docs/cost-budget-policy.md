# Cost budget policy

`platform-workloads` declares Azure budget policy. `platform-monitoring` owns the
budget resources; IDP displays the same remote-state data without maintaining
another policy catalog. Budgets notify only: they do not stop resources or cap
spending.

## Configuration

Set subscription amounts at `subscriptions[alias].monthly_budget` and shared
notification defaults at `cost_budget_defaults` in
[`prd.tfvars`](../terraform/tfvars/prd.tfvars). Subscription and workload
allowances are independent alerting limits, not allocations that must sum.
Amounts use the subscription's billing currency.

Declare workload defaults in the JSON `cost_budget` object. Override individual
fields on an `environments` entry's `cost_budget`. Resolution is environment,
then workload, then shared notification/start-date defaults. Arrays replace
rather than append. Omit a field to inherit it; null is not a workload override.
An empty actual or forecast array disables that alert type.

Each environment requires either a budget with a non-empty `rationale`, or a
non-empty `cost_budget_exemption` reason (environment overrides workload-level
exemption). Exemptions are not zero-cost estimates. Repository-only definitions
have no provisioned environment to budget. Keep amounts and concise rationale in
configuration rather than duplicating them in documentation.

Supported workload fields:

| Field | Usage |
| --- | --- |
| `monthly_budget` | Positive numeric monthly allowance |
| `rationale` | Reason for the allowance; identify reviewable initial allowances rather than inventing recurring baselines |
| `actual_thresholds`, `forecast_thresholds` | Arrays of percentages; inherit shared defaults when omitted |
| `contact_emails` | Recipient array; inherit shared defaults when omitted |
| `scope` | `subscription` by default, or `resource-group` for a single declared RG |
| `budget_name`, `start_date` | Optional identity overrides for adoption; preserve these during ownership transfers |

Optional subscription `cost_budget` overrides support notification arrays,
`budget_name`, `start_date` and a required `rationale`. See the typed schema in
[`variables.tf`](../terraform/variables.tf).

Every budgeted environment must declare resource groups. All its groups across
all locations share one allowance. Subscription-scope workload budgets require
the complete `ResourceGroupName` filter; consumers must never drop an invalid or
empty filter and broaden a workload budget to a subscription. Resource-group
scope requires exactly one declared group. Groups outside workload declarations,
including Terraform backend groups, remain covered by subscription budgets.

Validation requires 1-5 alerts total, unique within each type, with percentages
greater than zero and at most 1000; and 1-5 unique valid email recipients. Names
must be 1-63 alphanumeric, underscore or hyphen characters, starting with an
alphanumeric character. Start dates must be valid first-of-month UTC timestamps.
Scope/name identities must be unique. Unsupported JSON policy fields fail
validation rather than being ignored.

## Remote-state contract

`cost_budget_policies.version` is `1`. `subscriptions[alias]` contains:

`monthly_budget`, bare UUID `subscription_id`, full ARM `scope`, `budget_name`,
`start_date`, `actual_thresholds`, `forecast_thresholds`, `contact_emails`, and
`rationale` (nullable when no subscription override is declared).

`workload_environments["workload-Environment"]` contains these plus `workload`,
`environment`, `environment_tag`, and sorted distinct `resource_group_names`.
Keys preserve the case-sensitive workload/environment identity, not environment
tags. Consumers must use configured values rather than hard-coded amounts,
thresholds or environment counts. Existing `subscriptions` output fields remain
compatible. See the [consumer guide](consuming-platform-workloads-outputs.md).

Subscription names default to `budget-${subscription.name}`; new workload names
default to `${workload}-${environment_tag}-monthly`. Date defaults and explicit
legacy identity overrides are in configuration. Changing an adopted identity
requires a reviewed migration, not automatic replacement.

## Ownership and deployment

Publish producer outputs before deploying consumers. For existing budgets,
release the old owner's state with `removed` / `destroy = false`, then follow
monitoring's adoption runbook to import
`${scope}/providers/Microsoft.Consumption/budgets/${budget_name}`. Preserve the
scope, name and start date. Review the complete monitoring plan and adoption
approval before applying: no deletion, replacement, duplicate budget or scope
broadening. Deploy IDP consumption only after producer outputs exist.
