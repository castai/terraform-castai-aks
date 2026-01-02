mock_provider "azurerm" {
  mock_data "azurerm_kubernetes_cluster" {
    defaults = {
      location = "eastus"
      fqdn     = "test-cluster.eastus.azmk8s.io"
      network_profile = [{
        pod_cidr     = "10.244.0.0/16"
        service_cidr = "10.0.0.0/16"
      }]
    }
  }
}

mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      object_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "castai" {}
mock_provider "helm" {}
mock_provider "null" {}

variables {
  aks_cluster_name      = "test-cluster"
  aks_cluster_region    = "eastus"
  subscription_id       = "00000000-0000-0000-0000-000000000000"
  tenant_id             = "11111111-1111-1111-1111-111111111111"
  resource_group        = "test-rg"
  node_resource_group   = "test-node-rg"
  castai_api_token      = "test-token-12345"
  authentication_method = "workload_identity"
  default_node_configuration = "default"
  node_configurations = {
    default = {
      name    = "default"
      subnets = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/test-subnet"]
    }
  }
}

run "verify_workload_identity_resources_created" {
  command = plan

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Managed identity should be created for workload_identity auth"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 1
    error_message = "Federated identity credential should be created for workload_identity auth"
  }

  assert {
    condition     = length([for r in data.azurerm_kubernetes_cluster.castai : r]) == 1
    error_message = "AKS cluster data source should be queried for workload_identity auth"
  }

  assert {
    condition     = length([for r in data.castai_impersonation_service_account.this : r]) == 1
    error_message = "CAST AI impersonation service account data source should be queried"
  }
}

run "verify_client_secret_resources_not_created" {
  command = plan

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 0
    error_message = "Azure AD application should NOT be created for workload_identity auth"
  }

  assert {
    condition     = length([for r in azuread_application_password.castai : r]) == 0
    error_message = "Azure AD application password should NOT be created for workload_identity auth"
  }

  assert {
    condition     = length([for r in azuread_service_principal.castai : r]) == 0
    error_message = "Azure AD service principal should NOT be created for workload_identity auth"
  }
}

run "verify_cluster_configuration_workload_identity" {
  command = plan

  assert {
    condition     = castai_aks_cluster.castai_cluster.client_secret == null
    error_message = "client_secret should be null for workload_identity auth"
  }
}

run "verify_federated_identity_configuration" {
  command = plan

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r if r.issuer == "https://accounts.google.com"]) == 1
    error_message = "Federated identity issuer should be 'https://accounts.google.com'"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r if contains(r.audience, "api://AzureADTokenExchange")]) == 1
    error_message = "Federated identity audience should include 'api://AzureADTokenExchange'"
  }
}

run "verify_managed_identity_name" {
  command = plan

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r if r.name == "test-cluster-castai-identity"]) == 1
    error_message = "Managed identity name should follow the pattern '{cluster_name}-castai-identity'"
  }
}

