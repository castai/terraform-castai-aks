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
  aks_cluster_name   = "test-cluster"
  aks_cluster_region = "eastus"
  subscription_id    = "00000000-0000-0000-0000-000000000000"
  tenant_id          = "11111111-1111-1111-1111-111111111111"
  resource_group     = "test-rg"
  node_resource_group = "test-node-rg"
  castai_api_token   = "test-token-12345"
  default_node_configuration = "default"
  node_configurations = {
    default = {
      name    = "default"
      subnets = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/test-subnet"]
    }
  }
}

run "invalid_authentication_method" {
  command = plan

  variables {
    authentication_method = "invalid_method"
  }

  expect_failures = [
    var.authentication_method,
  ]
}

run "valid_client_secret_authentication_method" {
  command = plan

  variables {
    authentication_method = "client_secret"
  }

  assert {
    condition     = var.authentication_method == "client_secret"
    error_message = "Should accept 'client_secret' as valid authentication_method"
  }
}

run "valid_workload_identity_authentication_method" {
  command = plan

  variables {
    authentication_method = "workload_identity"
  }

  assert {
    condition     = var.authentication_method == "workload_identity"
    error_message = "Should accept 'workload_identity' as valid authentication_method"
  }
}
