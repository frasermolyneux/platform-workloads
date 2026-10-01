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
  }))
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
