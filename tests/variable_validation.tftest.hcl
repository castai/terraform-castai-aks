mock_provider "azurerm" {
  mock_data "azurerm_kubernetes_cluster" {
    defaults = {
      location        = "eastus"
      fqdn            = "test-cluster.eastus.azmk8s.io"
      oidc_issuer_url = "https://accounts.google.com"
      network_profile = [{
        pod_cidr           = "10.244.0.0/16"
        service_cidr       = "10.0.0.0/16"
        dns_service_ip     = "10.0.0.10"
        docker_bridge_cidr = "172.17.0.1/16"
        load_balancer_sku  = "standard"
        network_plugin     = "azure"
        network_policy     = "azure"
        outbound_type      = "loadBalancer"
      }]
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test-cluster-castai-identity"
      principal_id = "66666666-6666-6666-6666-666666666666"
      client_id    = "77777777-7777-7777-7777-777777777777"
    }
  }

  mock_resource "azurerm_federated_identity_credential" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test-cluster-castai-identity/federatedIdentityCredentials/castai-federation"
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

run "default_authentication_method_is_workload_identity" {
  command = plan

  assert {
    condition     = var.authentication_method == "workload_identity"
    error_message = "Default authentication_method should be 'workload_identity'"
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

run "default_authentication_method_migration_is_none" {
  command = plan

  assert {
    condition     = var.authentication_method_migration == "none"
    error_message = "Default migration should be 'none'"
  }
}

run "valid_migration_value_none" {
  command = plan

  variables {
    authentication_method_migration = "none"
  }

  assert {
    condition     = contains(["prepare", "none", "keep-secret-auth"], var.authentication_method_migration)
    error_message = "Should accept 'none' as valid migration"
  }
}

run "valid_migration_value_keep_secret_auth" {
  command = plan

  variables {
    authentication_method_migration = "keep-secret-auth"
  }

  assert {
    condition     = var.authentication_method_migration == "keep-secret-auth"
    error_message = "Should accept 'keep-secret-auth' as valid migration"
  }
}

run "separate_autoscaler_policies_and_evictor_settings" {
  command = plan

  variables {
    autoscaler_settings = {
      enabled     = true
      scoped_mode = true
      unschedulable_pods = {
        enabled                            = true
        partial_template_matching_enabled = true
      }
      node_downscaler = {
        empty_nodes_enabled = true
        empty_nodes_delay   = "120s"
      }
    }
    evictor_settings = {
      enabled = true
      dry_run = true
    }
  }

  assert {
    condition     = castai_autoscaler_policies.castai_autoscaler_policies[0].scoped_mode == true
    error_message = "Autoscaler policies should use the V2 scoped_mode field"
  }

  assert {
    condition     = castai_autoscaler_policies.castai_autoscaler_policies[0].unschedulable_pods[0].partial_template_matching_enabled == true
    error_message = "Partial template matching should be nested under unschedulable_pods"
  }

  assert {
    condition     = castai_autoscaler_policies.castai_autoscaler_policies[0].node_downscaler[0].empty_nodes_delay == "120s"
    error_message = "Node downscaler should use the V2 empty_nodes_delay duration"
  }

  assert {
    condition     = castai_evictor.castai_evictor[0].enabled == true && castai_evictor.castai_evictor[0].dry_run == true
    error_message = "Evictor settings should be mapped independently from autoscaler policies"
  }
}

run "null_autoscaler_and_evictor_settings" {
  command = plan

  assert {
    condition     = length(castai_autoscaler_policies.castai_autoscaler_policies) == 0
    error_message = "Null autoscaler settings should not create a policies resource"
  }

  assert {
    condition     = length(castai_evictor.castai_evictor) == 0
    error_message = "Null evictor settings should not create an evictor resource"
  }
}

run "policy_settings_without_optional_nested_blocks" {
  command = plan

  variables {
    autoscaler_settings = {
      enabled = true
    }
  }

  assert {
    condition     = length(castai_autoscaler_policies.castai_autoscaler_policies[0].unschedulable_pods) == 0
    error_message = "Unset unschedulable_pods should not emit a default block"
  }

  assert {
    condition     = length(castai_autoscaler_policies.castai_autoscaler_policies[0].cluster_limits) == 0
    error_message = "Unset cluster_limits should not emit a default block"
  }

  assert {
    condition     = length(castai_autoscaler_policies.castai_autoscaler_policies[0].node_downscaler) == 0
    error_message = "Unset node_downscaler should not emit a default block"
  }

  assert {
    condition     = length(castai_evictor.castai_evictor) == 0
    error_message = "Evictor should remain independent and unset"
  }
}
