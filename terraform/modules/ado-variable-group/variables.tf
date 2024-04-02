variable "workload_name" {}

variable "environment_name" {
  default = "Development"
}

variable "environment_tag" {
  default = "dev"
}

variable "devops_project" {}

variable "subscription" {}

variable "location" {
  default = "uksouth"
}

variable "instance" {
  default = "01"
}

variable "tags" {
  default = {}
}

variable "variables" {
  type = list(object({
    name  = string
    value = optional(string, null)
  }))
}

// Reference Data
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

    add_nuget_variable_group = optional(bool, false)

    features = optional(map(string), {
      "boards"       = "enabled"
      "repositories" = "enabled"
      "pipelines"    = "enabled"
      "testplans"    = "enabled"
      "artifacts"    = "enabled"
    })
  }))
}
