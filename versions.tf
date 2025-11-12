terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.7.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3"
    }
    castai = {
      source  = "castai/castai"
      version = ">= 8.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3"
    }
  }
}
