terraform {
  required_version = ">= 1.6.2"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.96.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = ">= 0.9.1"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.1.0"
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

data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

resource "random_id" "environment_id" {
  byte_length = 6
}

resource "time_rotating" "rotate" {
  rotation_days = 30
}
