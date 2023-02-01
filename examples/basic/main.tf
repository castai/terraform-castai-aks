provider "castai" {
  api_token = var.castai_api_token
}

provider "azurerm" {
  features {}
}

data "azurerm_subscription" "current" {}

provider "azuread" {
  tenant_id = data.azurerm_subscription.current.tenant_id
}

module "castai-aks-cluster" {
  source = "../../"

  aks_cluster_name   = var.aks_cluster_name
  aks_cluster_region = var.aks_cluster_region
  subscription_id    = data.azurerm_subscription.current.subscription_id
  tenant_id          = data.azurerm_subscription.current.tenant_id

  node_resource_group        = azurerm_kubernetes_cluster.this.node_resource_group
  resource_group             = azurerm_kubernetes_cluster.this.resource_group_name
  delete_nodes_on_disconnect = true

  default_node_configuration = module.castai-aks-cluster.castai_node_configurations["default"]

  node_configurations = {
    default = {
      disk_cpu_ratio = 25
      subnets        = [azurerm_subnet.internal.id]
      tags           = {
        "node-config" : "default"
      }
    }
  }

  node_templates = {
    spot_tmpl = {
      configuration_id = module.castai-aks-cluster.castai_node_configurations["default"]

      should_taint = true
      custom_label = {
        key = "custom-key"
        value = "label-value"
      }

      constraints = {
        fallback_restore_rate_seconds = 1800
        spot = true
        use_spot_fallbacks = true
        min_cpu = 4
        max_cpu = 100
        instance_families = {
          exclude = ["standard_DPLSv5"]
        }
        compute_optimized = false
        storage_optimized = false
      }
    }
  }

}
