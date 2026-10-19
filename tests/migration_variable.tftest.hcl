# Tests the authentication_method_migration variable introduced in 12.x.x:
#   prepare (default) - pre-provision workload identity resources while
#                       authentication_method is client_secret
#   none              - opt out of any migration behavior
#
# The apply runs at the end exercise the prep lifecycle:
# prep -> un-prep with none (removes only the pre-provisioned resources).

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

# Defaults: client_secret auth + prepare migration.
# Workload identity resources are pre-provisioned but unused: the cluster
# registration and role assignments stay on the Azure AD service principal.
run "verify_defaults_pre_provision_workload_identity" {
  command = plan

  assert {
    condition     = var.authentication_method == "client_secret" && var.authentication_method_migration == "prepare"
    error_message = "Defaults should be client_secret auth with prepare migration"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should be created for client_secret auth"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Managed identity should be pre-provisioned by prepare"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 1
    error_message = "Federated identity credential should be pre-provisioned by prepare"
  }

  assert {
    condition     = length([for r in data.azurerm_kubernetes_cluster.castai : r]) == 1
    error_message = "AKS cluster data source should be read by prepare"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.client_secret != null
    error_message = "Cluster registration should still use client_secret with prepare"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.federation_id == null
    error_message = "Cluster registration should not use federation with prepare"
  }

  assert {
    condition     = azurerm_role_assignment.castai_resource_group.principal_id == "55555555-5555-5555-5555-555555555555"
    error_message = "Role assignments should stay on the service principal with prepare"
  }
}

# Opt-out: none keeps the previous behavior exactly - no workload identity
# resources, no data source reads, no extra permissions required.
run "verify_none_opts_out_of_prep" {
  command = plan

  variables {
    authentication_method_migration = "none"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should still be created with none"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 0
    error_message = "Managed identity should NOT be created with none"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 0
    error_message = "Federated identity credential should NOT be created with none"
  }

  assert {
    condition     = length([for r in data.azurerm_kubernetes_cluster.castai : r]) == 0
    error_message = "AKS cluster data source should NOT be read with none"
  }

  assert {
    condition     = length([for r in data.castai_impersonation_service_account.this : r]) == 0
    error_message = "CAST AI impersonation service account should NOT be read with none"
  }
}

# prepare has no additional effect once on workload_identity.
run "verify_prepare_is_noop_for_workload_identity" {
  command = plan

  variables {
    authentication_method = "workload_identity"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 0
    error_message = "Azure AD application should NOT be created for workload_identity + prepare"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Managed identity should exist for workload_identity + prepare"
  }
}

# none + workload_identity preserves the pre-migration-variable behavior.
run "verify_none_with_workload_identity" {
  command = plan

  variables {
    authentication_method = "workload_identity"
    authentication_method_migration = "none"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 0
    error_message = "Azure AD application should NOT be created for workload_identity + none"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Managed identity should exist for workload_identity + none"
  }
}

# --- Prep lifecycle (apply runs share state) ---

# Step 1: apply the defaults (client_secret + prepare): both auth resource
# sets exist; registration is still on the service principal.
run "apply_defaults_with_prep" {
  command = apply

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should exist after prep apply"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Managed identity should exist after prep apply"
  }
}

# Step 2: opting out later must only remove the pre-provisioned workload
# identity resources; the client_secret setup is untouched.
run "plan_unprep_with_none" {
  command = plan

  variables {
    authentication_method_migration = "none"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 0
    error_message = "Managed identity should be removed by the un-prep plan"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 0
    error_message = "Federated identity credential should be removed by the un-prep plan"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should be untouched by the un-prep plan"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.client_secret != null
    error_message = "Registration should stay on client_secret in the un-prep plan"
  }
}

# Step 3: apply the un-prep. Destroy-only for the workload identity resources.
run "apply_unprep_with_none" {
  command = apply

  variables {
    authentication_method_migration = "none"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 0
    error_message = "Managed identity should be removed from state by the un-prep apply"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 0
    error_message = "Federated identity credential should be removed from state by the un-prep apply"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should remain after the un-prep apply"
  }
}
