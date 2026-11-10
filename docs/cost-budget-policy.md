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

Each environment requires either a budget, or a
non-empty `cost_budget_exemption` reason (environment overrides workload-level
exemption). Exemptions are not zero-cost estimates. Repository-only definitions
have no provisioned environment to budget. Keep policy values in configuration
rather than duplicating them in documentation. Optional `rationale` is for useful
durable context, not mandatory commentary.

Supported workload fields:

| Field | Usage |
| --- | --- |
| `monthly_budget` | Positive numeric monthly allowance |
| `rationale` | Optional explanatory string; omitted values are published as null |
| `actual_thresholds`, `forecast_thresholds` | Arrays of percentages; inherit shared defaults when omitted |
| `contact_emails` | Recipient array; inherit shared defaults when omitted |
| `scope` | `subscription` by default, or `resource-group` for a single declared RG |
| `budget_name`, `start_date` | Optional identity overrides; preserve configured values to avoid budget replacement |

Optional subscription `cost_budget` overrides support notification arrays,
`budget_name`, `start_date` and optional `rationale`. See the typed schema in
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
`rationale` (null when omitted).

`workload_environments["workload-Environment"]` contains these plus `workload`,
`environment`, `environment_tag`, and sorted distinct `resource_group_names`.
Keys preserve the case-sensitive workload/environment identity, not environment
tags. Consumers must use configured values rather than hard-coded amounts,
thresholds or environment counts. Existing `subscriptions` output fields remain
compatible. See the [consumer guide](consuming-platform-workloads-outputs.md).

Subscription names default to `budget-${subscription.name}`; new workload names
default to `${workload}-${environment_tag}-monthly`. Date defaults and explicit
identity overrides are in configuration. Changing an existing identity
requires a reviewed migration, not automatic replacement.

## Ownership and deployment

`platform-workloads` owns the IDP collector's subscription RBAC using its existing
Production authority. IDP owns the collector identity and publishes its client ID
as `IDP_COLLECTOR_CLIENT_ID` in the repository's `Production` GitHub environment.
The producer checks that variable against the independently resolved, unique
Entra application `MX.IO IDP host collector (prd)` in its deployment tenant, then
resolves the service principal from the checked application. Missing, ambiguous,
malformed or mismatched identities fail the plan. Changing only the GitHub
variable cannot redirect grants; Entra registration changes remain a trusted
directory-administration operation. There is no reverse IDP state dependency or
copied principal ID.

The host worker uses the existing collector application and service principal
with certificate authentication; the display-name change does not replace that
identity or its subscription assignments. The portal application does not receive
cost access. Apply the IDP identity rename before planning this stack, retaining
the `IDP_COLLECTOR_CLIENT_ID` publication. See the
[collector cutover guide](idp-collector-cutover.md) for ordering and host secret access.

The locked GitHub provider's plural environment-variable data source persists
all nonsecret IDP Production variable values in producer state, not only the
client ID. It does not read Actions secrets. Keep credentials out of variables
and restrict state access accordingly.

The collector receives built-in **Cost Management Reader** on each distinct
subscription in the policy contract, including subscriptions with workload-only
policies. This role includes resource-group reads and the explicitly accepted
`Microsoft.Support/*` support-ticket permissions; it is not a custom query-only
role. No additional Reader role or new deployment delegation is required. IDP
must not also manage these assignments.

Publish producer outputs before deploying monitoring and IDP consumers. Review
the complete monitoring plan for unintended deletion, replacement, duplicate
budgets or scope broadening. Preserve configured scope, name and start date.
