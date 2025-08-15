terraform {
  required_version = ">= 1.11.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.6.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = ">= 1.9.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.6.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {}

  storage_use_azuread = true
}

provider "azapi" {
}

provider "azuredevops" {
  org_service_url = "https://dev.azure.com/frasermolyneux/"
}

provider "github" {
  owner = "frasermolyneux"
}
