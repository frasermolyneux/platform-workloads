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

variable "workloads" {
  type = list(object({
    name = string
    github = object({
      description = string
      topics      = optional(list(string), [])

      // For the below; if true then the secrets will either be added to the GitHub repository
      add_sonarcloud_secrets = optional(bool, false)
      add_nuget_environment  = optional(bool, false)

      visibility = optional(string, "private")

      has_downloads = optional(bool, true)
      has_issues    = optional(bool, true)
      has_projects  = optional(bool, true)
      has_wiki      = optional(bool, true)
    })

    environments = optional(list(object({
      name         = string
      subscription = string // Index name from the subscriptions variable

      connect_to_github               = optional(bool, false)      // If true, the SPN for the environment will be updated with a federated credential for the repository and added to the environment for use in GitHub Actions
      add_deploy_script_identity      = optional(bool, false)      // If true, a deploy script user assigned identity will be created and added to the environment for use in ARM deployments. Will be given same permissions as deploy principal.
      configure_for_terraform         = optional(bool, false)      // If true, a resource group, storage account and permissions will be set per environment for the Terraform state file
      requires_terraform_state_access = optional(list(string), []) // Names of other workloads whose Terraform state should be readable for the same environment
      devops_project                  = optional(string, null)     // If set, the SPN for the environment will have a credential added and the service connection created in the Azure DevOps project
      devops_create_variable_group    = optional(bool, false)      // If true, a variable group will be created in the Azure DevOps project with a backing key vault

      role_assignments = optional(list(object({
        scope            = string
        role_definitions = list(string)
      })), [])

      directory_roles = optional(list(string), [])
    })), [])

    create_dev_center_project = optional(bool, false)
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
