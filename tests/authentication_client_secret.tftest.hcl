mock_provider "azurerm" {
  mock_data "azurerm_kubernetes_cluster" {
    defaults = {
      location = "eastus"
      fqdn     = "test-cluster.eastus.azmk8s.io"
      network_profile = [{
        pod_cidr           = "10.244.0.0/16"
        service_cidr       = "10.0.0.0/16"
        dns_service_ip     = "10.0.0.10"
        docker_bridge_cidr = "172.17.0.1/16"
        load_balancer_sku  = "standard"
        network_plugin     = "azure"
        network_policy     = "azure"
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

  mock_resource "azuread_application" {
    defaults = {
      client_id = "22222222-2222-2222-2222-222222222222"
      id        = "/applications/22222222-2222-2222-2222-222222222222"
      object_id = "33333333-3333-3333-3333-333333333333"
    }
  }

  mock_resource "azuread_application_password" {
    defaults = {
      id    = "/applications/22222222-2222-2222-2222-222222222222/passwords/44444444-4444-4444-4444-444444444444"
      value = "mock-password-value"
    }
  }

  mock_resource "azuread_service_principal" {
    defaults = {
      id        = "/servicePrincipals/55555555-5555-5555-5555-555555555555"
      object_id = "55555555-5555-5555-5555-555555555555"
    }
  }
}

mock_provider "castai" {
  mock_resource "castai_aks_cluster" {
    defaults = {
      id = "88888888-8888-8888-8888-888888888888"
    }
  }

  mock_resource "castai_node_configuration" {
    defaults = {
      id = "99999999-9999-9999-9999-999999999999"
    }
  }

  mock_data "castai_impersonation_service_account" {
    defaults = {
      id = "system:serviceaccount:castai-agent:castai-agent"
    }
  }
}

mock_provider "helm" {}
mock_provider "null" {}

variables {
  aks_cluster_name    = "test-cluster"
  aks_cluster_region  = "eastus"
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  tenant_id           = "11111111-1111-1111-1111-111111111111"
  resource_group      = "test-rg"
  node_resource_group = "test-node-rg"
  castai_api_token    = "test-token-12345"
  default_node_configuration = "default"
  node_configurations = {
    default = {
      name    = "default"
      subnets = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/test-subnet"]
    }
  }
}

run "verify_default_authentication_method" {
  command = plan

  assert {
    condition     = var.authentication_method == "client_secret"
    error_message = "Default authentication_method should be 'client_secret'"
  }
}

run "verify_client_secret_resources_created" {
  command = plan

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should be created for client_secret auth"
  }

  assert {
    condition     = length([for r in azuread_application_password.castai : r]) == 1
    error_message = "Azure AD application password should be created for client_secret auth"
  }

  assert {
    condition     = length([for r in azuread_service_principal.castai : r]) == 1
    error_message = "Azure AD service principal should be created for client_secret auth"
  }
}

run "verify_workload_identity_resources_not_created" {
  command = plan

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 0
    error_message = "Managed identity should NOT be created for client_secret auth"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 0
    error_message = "Federated identity credential should NOT be created for client_secret auth"
  }

  assert {
    condition     = length([for r in data.azurerm_kubernetes_cluster.castai : r]) == 0
    error_message = "AKS cluster data source should NOT be queried for client_secret auth"
  }

  assert {
    condition     = length([for r in data.castai_impersonation_service_account.this : r]) == 0
    error_message = "CAST AI impersonation service account should NOT be queried for client_secret auth"
  }
}

run "verify_cluster_configuration_client_secret" {
  command = plan

  assert {
    condition     = castai_aks_cluster.castai_cluster.federation_id == null
    error_message = "federation_id should be null for client_secret auth"
  }
}
