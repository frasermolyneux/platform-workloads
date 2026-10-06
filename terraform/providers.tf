terraform {
  required_version = ">= 1.15.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.7.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.13.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13.0"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
      # Hold below 5.23.0: that release (Cloudflare Go SDK v7.8.0) regressed
      # Global API Key auth, returning "Invalid format for X-Auth-Email/X-Auth-Key
      # header" (Cloudflare API errors 6102/6103) on every zone lookup. Remove this
      # ceiling once the stack migrates to API Token auth (CLOUDFLARE_API_TOKEN).
      version = ">= 5.18, < 5.23.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.1"
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

provider "github" {
  owner = "frasermolyneux"
}

provider "cloudflare" {
}
