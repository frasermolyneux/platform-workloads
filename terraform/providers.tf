terraform {
  required_version = ">= 1.6.2"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = ">= 0.9.1"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.2.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}

provider "azuredevops" {
  org_service_url = "https://dev.azure.com/frasermolyneux/"
}

provider "github" {
  owner = "frasermolyneux"
}
