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

variable "github_service_connection_pat" {
  description = "Personal access token used for Azure DevOps GitHub service connections"
  type        = string
  sensitive   = true
}

variable "resource_providers" {
  description = "Azure Resource Providers to register in every managed subscription. Downstream workloads use resource_provider_registrations = none so registration is handled centrally here."
  type        = list(string)
  default = [
    "Microsoft.ADHybridHealthService",
    "Microsoft.Advisor",
    "Microsoft.ApiManagement",
    "Microsoft.AppConfiguration",
    "Microsoft.AppPlatform",
    "Microsoft.Authorization",
    "Microsoft.Automation",
    "Microsoft.AVS",
    "Microsoft.Billing",
    "Microsoft.Blueprint",
    "Microsoft.BotService",
    "Microsoft.Cache",
    "Microsoft.Cdn",
    "Microsoft.ChangeSafety",
    "Microsoft.ClassicSubscription",
    "Microsoft.CognitiveServices",
    "Microsoft.Commerce",
    "Microsoft.Compute",
    "Microsoft.Consumption",
    "Microsoft.ContainerInstance",
    "Microsoft.ContainerRegistry",
    "Microsoft.ContainerService",
    "Microsoft.CostManagement",
    "Microsoft.CustomProviders",
    "Microsoft.Databricks",
    "Microsoft.DataFactory",
    "Microsoft.DataLakeAnalytics",
    "Microsoft.DataLakeStore",
    "Microsoft.DataMigration",
    "Microsoft.DataProtection",
    "Microsoft.DBforMariaDB",
    "Microsoft.DBforMySQL",
    "Microsoft.DBforPostgreSQL",
    "Microsoft.DesktopVirtualization",
    "Microsoft.Devices",
    "Microsoft.DevTestLab",
    "Microsoft.DocumentDB",
    "Microsoft.EventGrid",
    "Microsoft.EventHub",
    "Microsoft.Features",
    "Microsoft.GuestConfiguration",
    "Microsoft.HDInsight",
    "Microsoft.HealthcareApis",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.Kusto",
    "Microsoft.Logic",
    "Microsoft.MachineLearningServices",
    "Microsoft.Maintenance",
    "Microsoft.ManagedIdentity",
    "Microsoft.ManagedServices",
    "Microsoft.Management",
    "Microsoft.Maps",
    "Microsoft.MarketplaceOrdering",
    "Microsoft.Network",
    "Microsoft.NotificationHubs",
    "Microsoft.OperationalInsights",
    "Microsoft.OperationsManagement",
    "Microsoft.PolicyInsights",
    "Microsoft.Portal",
    "Microsoft.PowerBIDedicated",
    "Microsoft.RecoveryServices",
    "Microsoft.Relay",
    "Microsoft.ResourceGraph",
    "Microsoft.ResourceIntelligence",
    "Microsoft.ResourceNotifications",
    "Microsoft.Resources",
    "Microsoft.Search",
    "Microsoft.Security",
    "Microsoft.SecurityInsights",
    "Microsoft.SerialConsole",
    "Microsoft.ServiceBus",
    "Microsoft.ServiceFabric",
    "Microsoft.SignalRService",
    "Microsoft.Sql",
    "Microsoft.Storage",
    "Microsoft.StreamAnalytics",
    "Microsoft.Support",
    "Microsoft.Web",
  ]
}
