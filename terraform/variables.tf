variable "environment" {
  default = "dev"
}

variable "location" {
  default = "uksouth"
}

variable "instance" {
  default = "01"
}

variable "subscription_id" {
  type = string
}

variable "platform_workloads_backend_resource_group_name" {
  description = "Resource group containing the platform-workloads Terraform backend storage account"
  type        = string
}

variable "platform_workloads_backend_storage_account_name" {
  description = "Storage account name for the platform-workloads Terraform backend"
  type        = string
}

variable "tags" {
  default = {}
}

variable "subscriptions" {
  type = map(object({
    name            = string
    subscription_id = string
    environment     = string
    monthly_budget  = optional(number, null)
    cost_budget = optional(object({
      actual_thresholds   = optional(list(number))
      forecast_thresholds = optional(list(number))
      contact_emails      = optional(list(string))
      budget_name         = optional(string)
      start_date          = optional(string, "2026-04-01T00:00:00Z")
      rationale           = optional(string)
    }))
  }))

  validation {
    condition = alltrue([
      for subscription in var.subscriptions :
      subscription.monthly_budget == null ? subscription.cost_budget == null : subscription.monthly_budget > 0
    ])
    error_message = "Subscription monthly_budget must be positive; cost_budget requires a monthly_budget."
  }
}

variable "cost_budget_defaults" {
  description = "Shared alert-only monthly budget notification defaults, overridable by subscription or workload/environment policy. Amounts use the subscription billing currency (GBP in this estate)."
  type = object({
    actual_thresholds   = list(number)
    forecast_thresholds = list(number)
    contact_emails      = list(string)
    start_date          = string
  })
}

variable "environment_map" {
  default = {
    Development = "dev"
    Testing     = "tst"
    Production  = "prd"
  }
}

variable "administrative_units" {
  description = "Administrative Units managed by platform-workloads; keyed by short name."
  type = map(object({
    display_name = optional(string)
    description  = optional(string)
  }))
  default = {
    xtremeidiots-dev = {
      display_name = "XtremeIdiots Development"
    }
    xtremeidiots-prd = {
      display_name = "XtremeIdiots Production"
    }
    molyneux-io-dev = {
      display_name = "Molyneux.IO Development"
    }
    molyneux-io-prd = {
      display_name = "Molyneux.IO Production"
    }
  }
}
