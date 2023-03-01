<a href="https://cast.ai">
    <img src="https://cast.ai/wp-content/themes/cast/img/cast-logo-dark-blue.svg" align="right" height="100" />
</a>

Terraform module for connecting a AKS cluster to CAST AI
==================


Website: https://www.cast.ai

Requirements
------------

- [Terraform](https://www.terraform.io/downloads.html) 0.13+

Using the module
------------

A module to create Azure role and a service principal that can be used to connect to CAST AI

Requires `castai/castai`, `hashicorp/azurerm`, `hashicorp/azuread`, `hashicorp/helm` providers to be configured.

The required parameters can be provided manually or alternatively can be easily acquired from your AKS cluster resource or Azure RM subscription data source.

```hcl
module "castai-aks-cluster" {
  source = "castai/aks/castai"

  aks_cluster_name    = var.aks_cluster_name
  aks_cluster_region  = var.aks_cluster_region
  node_resource_group = azurerm_kubernetes_cluster.example.node_resource_group
  resource_group      = azurerm_kubernetes_cluster.example.resource_group_name

  delete_nodes_on_disconnect = true

  subscription_id = data.azurerm_subscription.current.subscription_id
  tenant_id       = data.azurerm_subscription.current.tenant_id

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
```
# Examples 

Usage examples are located in [terraform provider repo](https://github.com/castai/terraform-provider-castai/tree/master/examples/aks)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 0.13 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | >=2.22.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >=3.7.0 |
| <a name="requirement_castai"></a> [castai](#requirement\_castai) | >= 2.0.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >=2.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | >=2.22.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >=3.7.0 |
| <a name="provider_castai"></a> [castai](#provider\_castai) | >= 2.0.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >=2.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azuread_application.castai](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application_password.castai](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azuread_service_principal.castai](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/service_principal) | resource |
| [azurerm_role_assignment.castai_node_resource_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.castai_resource_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_definition.castai](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_definition) | resource |
| [castai_aks_cluster.castai_cluster](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/aks_cluster) | resource |
| [castai_autoscaler.castai_autoscaler_policies](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/autoscaler) | resource |
| [castai_node_configuration.this](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/node_configuration) | resource |
| [castai_node_configuration_default.this](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/node_configuration_default) | resource |
| [castai_node_template.this](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/node_template) | resource |
| [helm_release.castai_agent](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_cluster_controller](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_evictor](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_kvisor](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_spot_handler](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [azuread_client_config.current](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_agent_values"></a> [agent\_values](#input\_agent\_values) | List of YAML formatted string values for agent helm chart | `list(string)` | `[]` | no |
| <a name="input_aks_cluster_name"></a> [aks\_cluster\_name](#input\_aks\_cluster\_name) | Name of the cluster to be connected to CAST AI. | `string` | n/a | yes |
| <a name="input_aks_cluster_region"></a> [aks\_cluster\_region](#input\_aks\_cluster\_region) | Region of the AKS cluster | `string` | n/a | yes |
| <a name="input_api_url"></a> [api\_url](#input\_api\_url) | URL of alternative CAST AI API to be used during development or testing | `string` | `"https://api.cast.ai"` | no |
| <a name="input_autoscaler_policies_json"></a> [autoscaler\_policies\_json](#input\_autoscaler\_policies\_json) | Optional json object to override CAST AI cluster autoscaler policies | `string` | `""` | no |
| <a name="input_castai_components_labels"></a> [castai\_components\_labels](#input\_castai\_components\_labels) | Optional additional Kubernetes labels for CAST AI pods | `map` | `{}` | no |
| <a name="input_cluster_controller_values"></a> [cluster\_controller\_values](#input\_cluster\_controller\_values) | List of YAML formatted string values for cluster-controller helm chart | `list(string)` | `[]` | no |
| <a name="input_default_node_configuration"></a> [default\_node\_configuration](#input\_default\_node\_configuration) | ID of the default node configuration | `string` | n/a | yes |
| <a name="input_delete_nodes_on_disconnect"></a> [delete\_nodes\_on\_disconnect](#input\_delete\_nodes\_on\_disconnect) | Optionally delete Cast AI created nodes when the cluster is destroyed | `bool` | `false` | no |
| <a name="input_evictor_values"></a> [evictor\_values](#input\_evictor\_values) | List of YAML formatted string values for evictor helm chart | `list(string)` | `[]` | no |
| <a name="input_install_security_agent"></a> [install\_security\_agent](#input\_install\_security\_agent) | Optional flag for installation of security agent (https://docs.cast.ai/product-overview/console/security-insights/) | `bool` | `false` | no |
| <a name="input_kvisor_values"></a> [kvisor\_values](#input\_kvisor\_values) | List of YAML formatted string values for kvisor helm chart | `list(string)` | `[]` | no |
| <a name="input_node_configurations"></a> [node\_configurations](#input\_node\_configurations) | Map of AKS node configurations to create | `any` | `{}` | no |
| <a name="input_node_resource_group"></a> [node\_resource\_group](#input\_node\_resource\_group) | n/a | `string` | n/a | yes |
| <a name="input_node_templates"></a> [node\_templates](#input\_node\_templates) | Map of node templates to create | `any` | `{}` | no |
| <a name="input_resource_group"></a> [resource\_group](#input\_resource\_group) | n/a | `string` | n/a | yes |
| <a name="input_spot_handler_values"></a> [spot\_handler\_values](#input\_spot\_handler\_values) | List of YAML formatted string values for spot-handler helm chart | `list(string)` | `[]` | no |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Azure subscription ID | `string` | n/a | yes |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | n/a | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_castai_node_configurations"></a> [castai\_node\_configurations](#output\_castai\_node\_configurations) | Map of node configurations ids by name |
| <a name="output_castai_node_templates"></a> [castai\_node\_templates](#output\_castai\_node\_templates) | Map of node template by name |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | CAST.AI cluster id, which can be used for accessing cluster data using API |
<!-- END_TF_DOCS -->
