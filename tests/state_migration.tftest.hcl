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
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/existing-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/existing-cluster-castai-identity"
      principal_id = "66666666-6666-6666-6666-666666666666"
      client_id    = "77777777-7777-7777-7777-777777777777"
    }
  }

  mock_resource "azurerm_federated_identity_credential" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/existing-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/existing-cluster-castai-identity/federatedIdentityCredentials/castai-federation"
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
  aks_cluster_name   = "existing-cluster"
  aks_cluster_region = "eastus"
  subscription_id    = "00000000-0000-0000-0000-000000000000"
  tenant_id          = "11111111-1111-1111-1111-111111111111"
  resource_group     = "existing-rg"
  node_resource_group = "existing-node-rg"
  castai_api_token   = "test-token-12345"
  default_node_configuration = "default"
  node_configurations = {
    default = {
      name    = "default"
      subnets = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/existing-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/test-subnet"]
    }
  }
}

# Test 1: Explicit client_secret creates the same indexed resources.
# This represents users who explicitly set the authentication method.
#
# The moved blocks in iam.tf map state from module versions that predate the
# authentication_method variable onto these indexed addresses, e.g.
# azuread_application.castai -> azuread_application.castai[0]. The assertions
# below pin the destination addressing the moved blocks rely on; the remapping
# itself only triggers against state carrying the old addresses, which the
# test framework cannot seed as it always starts from empty. 
run "verify_explicit_client_secret_creates_same_resources" {
  command = plan

  variables {
    authentication_method = "client_secret"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Should create exactly one Azure AD application with [0] index"
  }

  assert {
    condition     = length([for r in azuread_application_password.castai : r]) == 1
    error_message = "Should create exactly one Azure AD application password with [0] index"
  }

  assert {
    condition     = length([for r in azuread_service_principal.castai : r]) == 1
    error_message = "Should create exactly one Azure AD service principal with [0] index"
  }
}

# Test 2: Verify resources use consistent indexing
# This ensures the conditional logic properly creates indexed resources
run "verify_consistent_resource_indexing" {
  command = plan

  # All three Azure AD resources should use the same count condition
  assert {
    condition     = length([for r in azuread_application.castai : r]) == length([for r in azuread_application_password.castai : r])
    error_message = "Application and password should have matching counts"
  }

  assert {
    condition     = length([for r in azuread_application_password.castai : r]) == length([for r in azuread_service_principal.castai : r])
    error_message = "Password and service principal should have matching counts"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == length([for r in azuread_service_principal.castai : r])
    error_message = "Application and service principal should have matching counts"
  }
}

# Test 3: Switching to workload_identity should remove old resources
# This tests the conditional logic works correctly
run "verify_switching_to_workload_identity" {
  command = plan

  variables {
    authentication_method = "workload_identity"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 0
    error_message = "Should not create Azure AD application when using workload_identity"
  }

  assert {
    condition     = length([for r in azuread_application_password.castai : r]) == 0
    error_message = "Should not create Azure AD application password when using workload_identity"
  }

  assert {
    condition     = length([for r in azuread_service_principal.castai : r]) == 0
    error_message = "Should not create Azure AD service principal when using workload_identity"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Should create managed identity when using workload_identity"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 1
    error_message = "Should create federated identity credential when using workload_identity"
  }
}

# Test 4: Role assignments reference correct principal based on auth method
run "verify_role_assignments_follow_auth_method" {
  command = plan

  variables {
    authentication_method = "client_secret"
  }

  # Role assignments should exist for both auth methods
  assert {
    condition     = azurerm_role_assignment.castai_resource_group != null
    error_message = "Role assignment for resource group should exist"
  }

  assert {
    condition     = azurerm_role_assignment.castai_node_resource_group != null
    error_message = "Role assignment for node resource group should exist"
  }
}
