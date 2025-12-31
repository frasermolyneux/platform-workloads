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
  }))
}

variable "azuredevops_projects" {
  type = list(object({
    name        = string
    description = string

    visibility = optional(string, "private")

    version_control    = optional(string, "Git")
    work_item_template = optional(string, "Agile")

    add_nuget_variable_group      = optional(bool, false)
    add_sonarcloud_variable_group = optional(bool, false)

    features = optional(map(string), {
      "boards"       = "enabled"
      "repositories" = "enabled"
      "pipelines"    = "enabled"
      "testplans"    = "enabled"
      "artifacts"    = "enabled"
    })
  }))
}



variable "environment_map" {
  default = {
    Development = "dev"
    Testing     = "tst"
    Production  = "prd"
  }
}

variable "github_service_connection_pat" {
  description = "Personal access token used for Azure DevOps GitHub service connections"
  type        = string
  sensitive   = true
}
