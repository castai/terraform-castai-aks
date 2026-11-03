# Tests the authentication_method_migration variable:
#   prepare          - pre-provision workload identity resources while authentication stays on client_secret
#   keep-secret-auth - keep the Azure AD application, service principal and secret while
#                      authenticating with workload_identity
#   none (default)   - opt out of any migration behavior
#
# Matrix: (migration, authentication_method) -> resources
#   (none, workload_identity) default      -> workload identity only
#   (none, client_secret)                  -> client secret only (legacy behavior)
#   (prepare, client_secret)               -> both; authentication stays on client secret
#   (prepare, workload_identity)           -> no effect beyond workload identity
#   (keep-secret-auth, client_secret)      -> no effect beyond client secret
#   (keep-secret-auth, workload_identity)  -> both; authentication uses workload identity
#
# The apply runs at the end exercise the cutover lifecycle:
# client_secret -> keep-secret-auth + workload_identity -> none (drops the kept secret).

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

# Defaults: workload_identity auth + none migration. Only the workload identity
# resources exist; no Active Directory resources anywhere.
run "verify_defaults_are_workload_identity_only" {
  command = plan

  assert {
    condition     = var.authentication_method == "workload_identity" && var.authentication_method_migration == "none"
    error_message = "Defaults should be workload_identity auth with none migration"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 0
    error_message = "Azure AD application should NOT be created by default"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Managed identity should exist by default"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 1
    error_message = "Federated identity credential should exist by default"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.client_secret == null
    error_message = "Cluster registration should not use client_secret by default"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.federation_id == "66666666-6666-6666-6666-666666666666"
    error_message = "Cluster registration should use the managed identity principal by default"
  }

  assert {
    condition     = azurerm_role_assignment.castai_resource_group.principal_id == "66666666-6666-6666-6666-666666666666"
    error_message = "Role assignments should be on the managed identity by default"
  }
}

# Legacy setup, made explicit: none + client_secret behaves exactly as before
# the variable existed - client secret resources only, no data source reads.
run "verify_none_with_client_secret" {
  command = plan

  variables {
    authentication_method           = "client_secret"
    authentication_method_migration = "none"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should be created with client_secret"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 0
    error_message = "Managed identity should NOT be created with client_secret + none"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 0
    error_message = "Federated identity credential should NOT be created with client_secret + none"
  }

  assert {
    condition     = length([for r in data.azurerm_kubernetes_cluster.castai : r]) == 0
    error_message = "AKS cluster data source should NOT be read with client_secret + none"
  }

  assert {
    condition     = length([for r in data.castai_impersonation_service_account.this : r]) == 0
    error_message = "CAST AI impersonation service account should NOT be read with client_secret + none"
  }
}

# prepare pre-provisions the workload identity resources for a later switch
# while authentication stays on the Azure AD service principal.
run "verify_prepare_provisions_for_client_secret" {
  command = plan

  variables {
    authentication_method           = "client_secret"
    authentication_method_migration = "prepare"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should be created with client_secret + prepare"
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

# prepare has no additional effect once on workload_identity.
run "verify_prepare_is_noop_for_workload_identity" {
  command = plan

  variables {
    authentication_method           = "workload_identity"
    authentication_method_migration = "prepare"
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

# none + workload_identity explicitly preserves the default behavior.
run "verify_none_with_workload_identity" {
  command = plan

  variables {
    authentication_method           = "workload_identity"
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

# keep-secret-auth + client_secret is a no-op: only the client secret
# resources exist, driven by the authentication method itself.
run "verify_keep_secret_auth_noop_for_client_secret" {
  command = plan

  variables {
    authentication_method           = "client_secret"
    authentication_method_migration = "keep-secret-auth"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should be created with client_secret + keep-secret-auth"
  }

  assert {
    condition     = length([for r in azuread_application_password.castai : r]) == 1
    error_message = "Application password should be created with client_secret + keep-secret-auth"
  }

  assert {
    condition     = length([for r in azuread_service_principal.castai : r]) == 1
    error_message = "Service principal should be created with client_secret + keep-secret-auth"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 0
    error_message = "Managed identity should NOT be created with client_secret + keep-secret-auth"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 0
    error_message = "Federated identity credential should NOT be created with client_secret + keep-secret-auth"
  }

  assert {
    condition     = length([for r in data.azurerm_kubernetes_cluster.castai : r]) == 0
    error_message = "AKS cluster data source should NOT be read with client_secret + keep-secret-auth"
  }
}

# keep-secret-auth + workload_identity: authentication uses workload identity
# while the Azure AD application, service principal and secret are kept.
run "verify_keep_secret_auth_with_workload_identity" {
  command = plan

  variables {
    authentication_method           = "workload_identity"
    authentication_method_migration = "keep-secret-auth"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should be kept with workload_identity + keep-secret-auth"
  }

  assert {
    condition     = length([for r in azuread_application_password.castai : r]) == 1
    error_message = "Application password should be kept with workload_identity + keep-secret-auth"
  }

  assert {
    condition     = length([for r in azuread_service_principal.castai : r]) == 1
    error_message = "Service principal should be kept with workload_identity + keep-secret-auth"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Managed identity should exist with workload_identity + keep-secret-auth"
  }

  assert {
    condition     = length([for r in azurerm_federated_identity_credential.this : r]) == 1
    error_message = "Federated identity credential should exist with workload_identity + keep-secret-auth"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.client_secret == null
    error_message = "Registration should not send the client secret when authenticating with workload identity"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.federation_id == "66666666-6666-6666-6666-666666666666"
    error_message = "Registration should use the managed identity principal with workload_identity + keep-secret-auth"
  }

  assert {
    condition     = azurerm_role_assignment.castai_resource_group.principal_id == "66666666-6666-6666-6666-666666666666"
    error_message = "Role assignments should be on the managed identity with workload_identity + keep-secret-auth"
  }
}

# --- Cutover lifecycle (apply runs share state) ---

# Step 1: apply the legacy client secret setup.
run "apply_client_secret_only" {
  command = apply

  variables {
    authentication_method           = "client_secret"
    authentication_method_migration = "none"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should exist after the client_secret apply"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 0
    error_message = "Managed identity should NOT exist after the client_secret apply"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.client_secret == "mock-password-value"
    error_message = "Registration should carry the client_secret value after the apply"
  }
}

# Step 2: switch to workload identity while keeping the client secret
# resources. Only the workload identity resources are created; nothing is
# destroyed, and the registration moves to the managed identity in place.
run "plan_switch_to_workload_identity_with_keep_secret_auth" {
  command = plan

  variables {
    authentication_method           = "workload_identity"
    authentication_method_migration = "keep-secret-auth"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should be kept by the keep-secret-auth switch plan"
  }

  assert {
    condition     = length([for r in azuread_application_password.castai : r]) == 1
    error_message = "Application password should be kept by the keep-secret-auth switch plan"
  }

  assert {
    condition     = length([for r in azuread_service_principal.castai : r]) == 1
    error_message = "Service principal should be kept by the keep-secret-auth switch plan"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Managed identity should be added by the keep-secret-auth switch plan"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.client_secret == null
    error_message = "Registration should switch off the client secret in the keep-secret-auth switch plan"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.federation_id == "66666666-6666-6666-6666-666666666666"
    error_message = "Registration should switch to the managed identity principal in the keep-secret-auth switch plan"
  }
}

run "apply_switch_to_workload_identity_with_keep_secret_auth" {
  command = apply

  variables {
    authentication_method           = "workload_identity"
    authentication_method_migration = "keep-secret-auth"
  }

  assert {
    condition     = var.authentication_method == "workload_identity" && var.authentication_method_migration == "keep-secret-auth"
    error_message = "Applying the workload_identity switch with keep-secret-auth"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 1
    error_message = "Azure AD application should exist after the keep-secret-auth switch"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Managed identity should exist after the keep-secret-auth switch"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.federation_id == "66666666-6666-6666-6666-666666666666"
    error_message = "Registration should use the managed identity principal after the keep-secret-auth switch"
  }
}

# Step 3: drop keep-secret-auth: only the client secret resources are removed;
# the workload identity setup stays untouched.
run "plan_remove_keep_secret_auth" {
  command = plan

  variables {
    authentication_method           = "workload_identity"
    authentication_method_migration = "none"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 0
    error_message = "Azure AD application should be removed by the none plan"
  }

  assert {
    condition     = length([for r in azuread_application_password.castai : r]) == 0
    error_message = "Application password should be removed by the none plan"
  }

  assert {
    condition     = length([for r in azuread_service_principal.castai : r]) == 0
    error_message = "Service principal should be removed by the none plan"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Managed identity should stay in the none plan"
  }

  assert {
    condition     = castai_aks_cluster.castai_cluster.federation_id == "66666666-6666-6666-6666-666666666666"
    error_message = "Registration should keep using workload identity in the none plan"
  }
}

run "apply_remove_keep_secret_auth" {
  command = apply

  variables {
    authentication_method           = "workload_identity"
    authentication_method_migration = "none"
  }

  assert {
    condition     = length([for r in azuread_application.castai : r]) == 0
    error_message = "Azure AD application should be gone after removing keep-secret-auth"
  }

  assert {
    condition     = length([for r in azurerm_user_assigned_identity.this : r]) == 1
    error_message = "Managed identity should remain after removing keep-secret-auth"
  }
}
