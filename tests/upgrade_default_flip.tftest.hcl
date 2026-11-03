# Simulates the upgrade path for existing module users when the default
# authentication_method changed from client_secret to workload_identity.
# Run blocks execute sequentially against shared state within this file:
#   Phase 1: apply with the old default (client_secret) - existing user state
#   Phase 2: apply again with no override - the new default (workload_identity)
#            takes effect, migrating auth resources in one apply.

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
  aks_cluster_name           = "existing-cluster"
  aks_cluster_region         = "eastus"
  subscription_id            = "00000000-0000-0000-0000-000000000000"
  tenant_id                  = "11111111-1111-1111-1111-111111111111"
  resource_group             = "existing-rg"
  node_resource_group        = "existing-node-rg"
  castai_api_token           = "test-token-12345"
  default_node_configuration = "default"
  node_configurations = {
    default = {
      name    = "default"
      subnets = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/existing-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/test-subnet"]
    }
  }
}

# Phase 1: existing user state created with the OLD default (client_secret)
run "apply_old_default_client_secret" {
  command = apply

  variables {
    authentication_method = "client_secret"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Pre-upgrade: Azure AD application should exist in state"
  }

  assert {
    condition     = length([for r in azuread_application_password.castai : r]) == 1
    error_message = "Pre-upgrade: Azure AD application password should exist in state"
  }

  assert {
    condition     = length([for r in azuread_service_principal.castai : r]) == 1
    error_message = "Pre-upgrade: Azure AD service principal should exist in state"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 0
    error_message = "Pre-upgrade: managed identity should NOT exist in state"
  }
}

# Phase 2: user upgrades the module version without setting the variable.
# Planning against the Phase 1 state shows exactly what the upgrade apply does:
# destroy the Azure AD resources, create the managed identity and federated
# credential, and update the cluster registration auth fields in place.
run "plan_upgrade_new_default_workload_identity" {
  command = plan

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Upgrade plan: managed identity should be planned for creation"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 1
    error_message = "Upgrade plan: federated identity credential should be planned for creation"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 0
    error_message = "Upgrade plan: Azure AD application should be planned for destruction"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.federation_id == "66666666-6666-6666-6666-666666666666"
    error_message = "Upgrade plan: cluster registration should switch federation_id to the managed identity principal"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.client_id == "77777777-7777-7777-7777-777777777777"
    error_message = "Upgrade plan: cluster registration should switch client_id to the managed identity"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.client_secret == null
    error_message = "Upgrade plan: cluster registration should drop client_secret"
  }
}

# Phase 3: complete the upgrade - the migration apply succeeds.
run "apply_upgrade_new_default_workload_identity" {
  command = apply

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Post-upgrade: managed identity should exist in state"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 1
    error_message = "Post-upgrade: federated identity credential should exist in state"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 0
    error_message = "Post-upgrade: Azure AD application should be removed from state (destroyed)"
  }

  assert {
    condition     = length([for r in azuread_application_password.castai : r]) == 0
    error_message = "Post-upgrade: Azure AD application password should be removed from state (destroyed)"
  }

  assert {
    condition     = length([for r in azuread_service_principal.castai : r]) == 0
    error_message = "Post-upgrade: Azure AD service principal should be removed from state (destroyed)"
  }
}
