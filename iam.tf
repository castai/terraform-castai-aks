locals {
  role_name               = "CastAKSRole-${var.aks_cluster_name}-tf"
  app_name                = substr("CAST AI ${var.aks_cluster_name}-${var.resource_group}", 0, 64)
  federated_identity_name = substr("castai-${var.aks_cluster_name}-${var.resource_group}", 0, 64)
}

data "azurerm_kubernetes_cluster" "castai" {
  count               = var.authentication_method == "workload_identity" ? 1 : 0
  name                = var.aks_cluster_name
  resource_group_name = var.resource_group
}

// Azure RM
resource "azurerm_role_definition" "castai" {
  name        = local.role_name
  description = "Role used by CAST AI"

  scope = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group}"

  permissions {
    actions = [
      "Microsoft.Compute/*/read",
      "Microsoft.Compute/virtualMachines/*",
      "Microsoft.Compute/virtualMachineScaleSets/*",
      "Microsoft.Compute/disks/write",
      "Microsoft.Compute/disks/delete",
      "Microsoft.Compute/disks/beginGetAccess/action",
      "Microsoft.Compute/galleries/write",
      "Microsoft.Compute/galleries/delete",
      "Microsoft.Compute/galleries/images/write",
      "Microsoft.Compute/galleries/images/delete",
      "Microsoft.Compute/galleries/images/versions/write",
      "Microsoft.Compute/galleries/images/versions/delete",
      "Microsoft.Compute/snapshots/write",
      "Microsoft.Compute/snapshots/delete",
      "Microsoft.Network/*/read",
      "Microsoft.Network/networkInterfaces/write",
      "Microsoft.Network/networkInterfaces/delete",
      "Microsoft.Network/networkInterfaces/join/action",
      "Microsoft.Network/networkSecurityGroups/join/action",
      "Microsoft.Network/virtualNetworks/subnets/join/action",
      "Microsoft.Network/applicationGateways/backendhealth/action",
      "Microsoft.Network/applicationGateways/backendAddressPools/join/action",
      "Microsoft.Network/applicationSecurityGroups/joinIpConfiguration/action",
      "Microsoft.Network/loadBalancers/backendAddressPools/write",
      "Microsoft.Network/loadBalancers/backendAddressPools/join/action",
      "Microsoft.ContainerService/*/read",
      "Microsoft.ContainerService/managedClusters/runCommand/action",
      "Microsoft.ContainerService/managedClusters/agentPools/*",
      "Microsoft.Resources/*/read",
      "Microsoft.Resources/tags/write",
      "Microsoft.Authorization/locks/read",
      "Microsoft.Authorization/roleAssignments/read",
      "Microsoft.Authorization/roleDefinitions/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action"
    ]
    not_actions = []
  }

  assignable_scopes = distinct(compact(flatten([
    "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group}",
    "/subscriptions/${var.subscription_id}/resourceGroups/${var.node_resource_group}",
    var.additional_resource_groups
  ])))
}

resource "azurerm_role_assignment" "castai_resource_group" {
  principal_id       = var.authentication_method == "client_secret" ? azuread_service_principal.castai[0].object_id : azurerm_user_assigned_identity.this[0].principal_id
  role_definition_id = azurerm_role_definition.castai.role_definition_resource_id
  description        = "castai role assignment for resource group ${var.resource_group}"
  scope              = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group}"
}

resource "azurerm_role_assignment" "castai_node_resource_group" {
  principal_id       = var.authentication_method == "client_secret" ? azuread_service_principal.castai[0].object_id : azurerm_user_assigned_identity.this[0].principal_id
  role_definition_id = azurerm_role_definition.castai.role_definition_resource_id
  description        = "castai role assignment for resource group ${var.aks_cluster_name}"
  scope              = "/subscriptions/${var.subscription_id}/resourceGroups/${var.node_resource_group}"
}

resource "azurerm_role_assignment" "castai_additional_resource_groups" {
  for_each           = toset(var.additional_resource_groups)
  principal_id       = var.authentication_method == "client_secret" ? azuread_service_principal.castai[0].object_id : azurerm_user_assigned_identity.this[0].principal_id
  description        = "castai role assignment for resource group ${each.key}"
  role_definition_id = azurerm_role_definition.castai.role_definition_resource_id
  scope              = each.key
}

// Azure AD

data "azuread_client_config" "current" {}

resource "azuread_application" "castai" {
  count        = var.authentication_method == "client_secret" ? 1 : 0
  display_name = local.app_name
  owners       = (var.azuread_owners == null ? [data.azuread_client_config.current.object_id] : var.azuread_owners)
}

resource "azuread_application_password" "castai" {
  count          = var.authentication_method == "client_secret" ? 1 : 0
  application_id = azuread_application.castai[0].id
}

resource "azuread_service_principal" "castai" {
  count                        = var.authentication_method == "client_secret" ? 1 : 0
  client_id                    = azuread_application.castai[0].client_id
  app_role_assignment_required = false
  owners                       = (var.azuread_owners == null ? [data.azuread_client_config.current.object_id] : var.azuread_owners)
}

# State migration for existing users upgrading to authentication_method variable
moved {
  from = azuread_application.castai
  to   = azuread_application.castai[0]
}

moved {
  from = azuread_application_password.castai
  to   = azuread_application_password.castai[0]
}

moved {
  from = azuread_service_principal.castai
  to   = azuread_service_principal.castai[0]
}

// Workload Identity

data "castai_impersonation_service_account" "this" {
  count = var.authentication_method == "workload_identity" ? 1 : 0
}

resource "azurerm_user_assigned_identity" "this" {
  count               = var.authentication_method == "workload_identity" ? 1 : 0
  name                = "${var.aks_cluster_name}-castai-identity"
  resource_group_name = var.resource_group
  location            = data.azurerm_kubernetes_cluster.castai[0].location
}

resource "azurerm_federated_identity_credential" "this" {
  count               = var.authentication_method == "workload_identity" ? 1 : 0
  name                = local.federated_identity_name
  resource_group_name = var.resource_group
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://accounts.google.com"
  parent_id           = azurerm_user_assigned_identity.this[0].id
  subject             = data.castai_impersonation_service_account.this[0].id
}
