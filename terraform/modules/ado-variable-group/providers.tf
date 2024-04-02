terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.97.1"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = ">= 0.9.1"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuredevops" {
  org_service_url = "https://dev.azure.com/frasermolyneux/"
}
