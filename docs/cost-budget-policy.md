# Cost budget policy

`platform-workloads` is the source of truth for Azure cost allowances and alert
policy. `platform-monitoring` consumes `cost_budget_policies` from remote state
and owns the Azure budget resources. IDP displays the same data; it must not
maintain another amount/threshold catalog. This stack declares policy only:
it creates no Azure budgets, action groups, shutdowns or spending caps.

## Declaration and validation

Subscription amounts remain at `subscriptions[alias].monthly_budget` in
[`prd.tfvars`](../terraform/tfvars/prd.tfvars). Existing `subscriptions` output
fields are unchanged. An omitted/null amount means no subscription policy.
Optional `cost_budget` alongside the amount overrides notifications, budget
identity or start date and requires a non-empty `rationale`.

Workload JSON supports `cost_budget` at the workload level (defaults for its
environments) and on individual `environments` entries (field-by-field
overrides). Environment policy overrides workload policy, then shared
`cost_budget_defaults` supplies notification and new-workload start-date
defaults. Arrays replace rather than append; an empty actual or forecast
array disables that alert type, not the budget. Null is not a workload override:
omit the field to inherit it. Every environment requires a policy or an explicit
non-empty `cost_budget_exemption` reason (environment overrides workload-level
exemption). Exempt spend remains covered by the subscription policy, not assumed
to be zero. Repository-only entries do not receive workload budgets.

```json
{
  "cost_budget": {
    "monthly_budget": 5,
    "rationale": "Reviewable initial alert allowance, not a measured baseline."
  },
  "environments": [
    {
      "name": "Production",
      "subscription": "sub-platform-shared",
      "cost_budget": {
        "monthly_budget": 25,
        "actual_thresholds": [50, 80, 100],
        "forecast_thresholds": [100],
        "contact_emails": ["frasermolyneux@mx-mail.io"],
        "rationale": "October GBP 19.07 rounded up with buffer."
      }
    }
  ]
}
```

The snippet illustrates policy inheritance, not a complete workload definition.
See [workload configuration](workload-configuration.md) for resource-group
declarations. Every enrolled environment must declare at least one resource
group; all declared groups across all locations form one combined budget, not
one amount per group. Names are normalized by the existing workload loader.
The filter excludes Terraform backend groups and groups absent from the
workload definition; those remain covered by subscription budgets.

Supported workload policy fields are `monthly_budget`, `rationale`,
`actual_thresholds`, `forecast_thresholds`, `contact_emails`, `scope`,
`budget_name`, and `start_date`. `scope` defaults to `subscription`: consumers
must use a subscription budget with the complete `ResourceGroupName` filter.
`resource-group` is supported only when the environment has exactly one group
and is intended for legacy budget adoption. Consumers must never silently
drop an empty/invalid filter and broaden a workload budget to a subscription.

Amounts are positive numbers in the subscription's **billing currency** (GBP
for this estate), not currency conversions. Defaults are actual 50/80/100%,
forecast 100%, recipient `frasermolyneux@mx-mail.io`. There must be 1-5 alerts
total, unique within each type, each greater than 0 and at most 1000%; actual
and forecast may share a percentage. Recipients are 1-5 unique email addresses.
Budget names are 1-63 alphanumeric, underscore or hyphen characters, starting
with an alphanumeric character. Start dates must be valid first-of-month UTC
timestamps. Scope/name identities must be unique. Unsupported JSON policy
fields fail the `terraform_data.cost_budget_contract` precondition rather than
being silently ignored. Subscription overrides use the typed schema in
[`variables.tf`](../terraform/variables.tf).

## Initial recommendations (November 2026)

Amounts below are alerting allowances, not forecasts or promises of cost.
October is one complete sample; November 1-8 is only a sanity check and is
**not linearly extrapolated**. Review allowances after an ordinary full month
and whenever workload configuration materially changes.

| Subscription | Previous GBP | New GBP/month | Evidence and rationale |
| --- | ---: | ---: | --- |
| Portal | 100 | 200 | Workload allowances 160 + 40 headroom; October 120.57, November 23.83 partial |
| Shared | 150 | 75 | Workload allowances 55 + 20 headroom; October 106.30 minus 76.71 incident = 29.59, November 3.64 partial |
| MSDN / Visual Studio Enterprise | 200 | 200 | Retain safe coverage: workload allowances 130 + 70 variable development headroom; October 45.70, November 18.42 partial |
| Management | 50 | 150 | Workload allowances 110 + 40 headroom; October 44.37, November 7.66 partial |
| Connectivity | 20 | 20 | Retain safe coverage: workload allowance 15 + 5 headroom; October DNS 8.78, November 2.28 partial |

The subscription allowances are deliberately higher than the sum of their
non-overlapping RG workload allowances. Shared/unallocated headroom covers
backend infrastructure, landing-zone resources and other spend outside workload
filters; it is **not a measured recurring-cost baseline**. Conservative initial
workload allowances can collectively exceed observed subscription actuals,
particularly on management and development subscriptions. Reconcile after an
ordinary full month before tightening them.

Other subscriptions retain their existing safe coverage because no trustworthy
recurring evidence was supplied: enterprise-devtest-legacy 50, fm-geolocation
50, mx-consulting 30, identity 20, talkwithtiles 30, Visual Studio legacy 50,
xi-demomanager 30, finances 20, molyneux-me dev 20 and prod 20 (GBP/month).
Do not treat lack of a supplied sample as zero recurring cost.

| Workload environment | GBP/month | Basis |
| --- | ---: | --- |
| portal-core Production | 85 | October RG 68.16 plus modest buffer |
| portal-core Development | 35 | October RG 25.81 plus buffer |
| portal-environments Production | 35 | October RG 28.09 plus modest buffer |
| platform-hosting Production | 25 | October RG 19.07 plus buffer |
| platform-monitoring Production | 35 | October RG 26.45 plus buffer |
| platform-connectivity Production | 15 | October DNS RG 8.78, rounded up |
| platform-radar Production | 10 | Preserve existing allowance; October RG 4.92 is one sample |
| platform-developer-portal Production | 10 | Preserve existing reviewable initial allowance; no reliable RG baseline supplied |
| platform-notifications Development and Production | 5 each | Explicit reviewable initial allowance, **not** a recurring estimate |
| All other RG-backed workload environments | 5 each | Explicit reviewable initial unmeasured-usage allowances in workload JSON, not estimates of zero or recurring consumption |

Notifications' October RG total 77.39 was incident-dominated. Neither that
total nor subscription incident-adjusted arithmetic establishes a recurring
notifications baseline. The GBP 5 setting is deliberately an initial alert
allowance requiring review after one ordinary full month. Every other RG-backed
environment is explicitly enrolled with a configurable GBP 5 initial alert
allowance and source-controlled rationale, rather than estimating unknown
consumption as zero. Sitewatch's three production regions share one GBP 5
allowance. Baremetal allowances cover only declared Azure RG costs, not hosting
provider invoices.

The complete inventory is **58 environment declarations: 57 budgeted, one
exempt**. The sole exemption is `platform-landing-zones-Production`: it has no
declared workload RG, so constructing a granular filter would invent ownership.
Its costs remain under management's subscription budget. Repository-only
catalog rows have no provisioned environment to budget; example JSON is not
discovered. New environment declarations must carry a budget or reasoned
exemption, enforced by the Terraform precondition.

| Subscription | Workload allowances GBP | Subscription GBP | Shared/unallocated headroom GBP |
| --- | ---: | ---: | ---: |
| enterprise-devtest-legacy | 0 declared | 50 | 50 |
| fm-geolocation-prd | 0 declared | 50 | 50 |
| mx-consulting-prd | 0 declared | 30 | 30 |
| platform-connectivity | 15 | 20 | 5 |
| platform-identity | 0 declared | 20 | 20 |
| platform-management | 110 | 150 | 40 |
| platform-shared | 55 | 75 | 20 |
| talkwithtiles-prd | 0 declared | 30 | 30 |
| visualstudio-enterprise | 130 | 200 | 70 |
| visualstudio-enterprise-legacy | 0 declared | 50 | 50 |
| xi-demomanager-prd | 5 | 30 | 25 |
| xi-portal-prd | 160 | 200 | 40 |
| finances-prd | 0 declared | 20 | 20 |
| molyneux-me-dev | 10 | 20 | 10 |
| molyneux-me-prd | 10 | 20 | 10 |

Zero **declared allowances** does not mean zero subscription consumption:
unallocated/subscription-only infrastructure is deliberately not invented as a
workload. Alias placement follows existing catalog subscriptions, even where an
older dedicated subscription remains configured. Contract tests check that all
initial subscription allowances exceed the workload sum by at least 20%
(minimum GBP 5); no initial buffer exceptions are needed. RG filters are
non-overlapping within each subscription. These are alerting allowances, not
allocations or forecasts; actual subscription spend includes each charge once.

## Stable downstream contract and adoption

`cost_budget_policies.version` is `1`. `subscriptions[alias]` contains
`monthly_budget`, bare UUID `subscription_id`, full ARM `scope`, `budget_name`,
`start_date`, `actual_thresholds`, `forecast_thresholds`, `contact_emails`,
and `rationale` (null for unchanged legacy subscription allowances).
`workload_environments["workload-Environment"]` contains these plus `workload`,
`environment`, `environment_tag`, and sorted distinct `resource_group_names`.
Keys preserve the existing workload-environment identity, including display-name
case; they are not environment-tag keys. See the
[remote-state consumer guide](consuming-platform-workloads-outputs.md).

Subscription names remain `budget-${subscription.name}`, starting
`2026-04-01T00:00:00Z`. New workload names are
`${workload}-${environment_tag}-monthly`, starting `2026-11-01T00:00:00Z`.
Both identity and date can be explicitly overridden; changing them after
creation needs a reviewed migration, not automatic replacement.

Two existing GBP 10 budgets retain their full ARM identities and
`2026-10-01T00:00:00Z` start date:

| Workload key | Scope suffix under management subscription `7760848c-794d-4a19-8cb2-52f71a21ac2b` | Budget name |
| --- | --- | --- |
| `platform-radar-Production` | `/resourceGroups/rg-platform-radar-prd-uksouth` | `radar-monthly` |
| `platform-developer-portal-Production` | `/resourceGroups/rg-platform-developer-portal-prd-uksouth` | `idp-monthly-notification` |

The complete budget import ID is `${scope}/providers/Microsoft.Consumption/budgets/${budget_name}`.
Never deploy a competing subscription-filter budget for these two identities.

Approval/deployment order (operators only; this change performs none):

1. Review and merge this catalog contract; approve the full production plan and
   apply platform-workloads to publish remote-state outputs. Check that no
   unrelated resources are changed.
2. Merge/apply the reviewed Radar and IDP ownership-release changes using
   `removed` blocks with `destroy = false`. Verify their budgets remain in
   Azure and are no longer owned by those states.
3. Use platform-monitoring's adoption runbook to import the two exact existing
   IDs into its reviewed addresses. Preserve start dates and existing
   subscription addresses. Review the complete monitoring plan: no deletion,
   replacement, duplicate legacy budget or unintended scope broadening.
   Only then approve/apply monitoring's budget resources and notification policy.
4. Deploy IDP consumption after the remote-state contract exists. Verify amount,
   scope, actual/forecast thresholds and recipient visibility against catalog
   policy, and review notifications after a complete ordinary billing month.

Azure budgets [notify rather than stop resources](https://learn.microsoft.com/azure/cost-management-billing/costs/tutorial-acm-create-budgets);
cost ingestion and alert evaluation are delayed. An allowance is not an
immediate incident circuit breaker.
