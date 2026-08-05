terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0.1"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0"
    }
    castai = {
      source  = "castai/castai"
      version = ">= 8.55.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3"
    }
  }
}
