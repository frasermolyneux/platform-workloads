terraform {
  required_version = ">= 1.14.3"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.70.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.9.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = ">= 1.9.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.12.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.18"
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

provider "cloudflare" {
}
