<a href="https://cast.ai">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/full-logo-white.svg">
    <source media="(prefers-color-scheme: light)" srcset=".github/full-logo-black.svg">
    <img src=".github/full-logo-black.svg" alt="Cast AI logo" title="Cast AI" align="right" height="50">
  </picture>
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

      custom_labels = {
        custom-label-key-1 = "custom-label-value-1"
        custom-label-key-2 = "custom-label-value-2"
      }

      custom_taints = [
        {
          key = "custom-taint-key-1"
          value = "custom-taint-value-1"
        },
        {
          key = "custom-taint-key-2"
          value = "custom-taint-value-2"
        }
      ]

      constraints = {
        fallback_restore_rate_seconds = 1800
        spot = true
        use_spot_fallbacks = true
        min_cpu = 4
        max_cpu = 100
        instance_families = {
          exclude = ["standard_DPLSv5"]
        }
        compute_optimized_state = "disabled"
        storage_optimized_state = "disabled"
      }
    }
  }

  autoscaler_settings = {
    enabled                                 = true
    node_templates_partial_matching_enabled = false

    unschedulable_pods = {
      enabled = true
    }

    node_downscaler = {
      enabled = true

      empty_nodes = {
        enabled = true
      }

      evictor = {
        aggressive_mode           = false
        cycle_interval            = "5s10s"
        dry_run                   = false
        enabled                   = true
        node_grace_period_minutes = 10
        scoped_mode               = false
      }
    }

    cluster_limits = {
      enabled = true

      cpu = {
        max_cores = 20
        min_cores = 1
      }
    }
  }

  workload_scaling_policies = {
    default = {
      apply_type        = "IMMEDIATE"
      management_option = "MANAGED"

      cpu = {
        function                 = "QUANTILE"
        args                     = ["0.9"]
        overhead                 = 0.15
        look_back_period_seconds = 172800
        min                      = 0.1
        max                      = 2.0
      }

      memory = {
        function                 = "MAX"
        overhead                 = 0.35
        look_back_period_seconds = 172800

        limit = {
          type = "NOLIMIT"
        }
      }

      assignment_rules = {
        rules = [
          {
            namespace = {
              names = ["default", "kube-system"]
            }
          },
          {
            workload = {
              gvk: ["Deployment", "StatefulSet"]
              labels_expressions = [
                {
                  key      = "region"
                  operator = "NotIn"
                  values   = ["eu-west-1", "eu-west-2"]
                },
                {
                  key      = "helm.sh/chart"
                  operator = "Exists"
                }
              ]
            }
          }
        ]
      }

      startup = {
        period_seconds = 300
      }

      predictive_scaling = {
        cpu = {
          enabled = true
        }
      }
    }
  }
}
```

Migrating from 2.x.x to 3.x.x
---------------------------

Version 3.x.x changes:
* Removed `custom_label` attribute in `castai_node_template` resource. Use `custom_labels` instead.

Old configuration:
```terraform
module "castai-aks-cluster" {
  node_templates = {
    spot_tmpl = {
      custom_label = {
        key = "custom-label-key-1"
        value = "custom-label-value-1"
      }
    }
  }
}
```

New configuration:
```terraform
module "castai-aks-cluster" {
  node_templates = {
    spot_tmpl = {
      custom_labels = {
        custom-label-key-1 = "custom-label-value-1"
      }
    }
  }
}
```
Migrating from 3.x.x to 4.x.x
---------------------------

Version 4.x.x changed:
* Removed `compute_optimized` and `storage_optimized` attributes in `castai_node_template` resource, `constraints` object. Use `compute_optimized_state` and `storage_optimized_state` instead.

Old configuration:
```terraform
module "castai-aks-cluster" {
  node_templates = {
    spot_tmpl = {
      constraints = {
        compute_optimized = false
        storage_optimized = true
      }
    }
  }
}
```

New configuration:
```terraform
module "castai-aks-cluster" {
  node_templates = {
    spot_tmpl = {
      constraints = {
        compute_optimized_state = "disabled"
        storage_optimized_state = "enabled"
      }
    }
  }
}
```

Migrating from 5.0.x to 5.2.x
---------------------------

Version 5.2.x changed:
* Deprecated `autoscaler_policies_json` attribute. Use `autoscaler_settings` instead.

Old configuration:
```hcl
module "castai-aks-cluster" {
  autoscaler_policies_json = <<-EOT
    {
        "enabled": true,
        "unschedulablePods": {
            "enabled": true
        },
        "nodeDownscaler": {
            "enabled": true,
            "emptyNodes": {
                "enabled": true
            },
            "evictor": {
                "aggressiveMode": false,
                "cycleInterval": "5m10s",
                "dryRun": false,
                "enabled": true,
                "nodeGracePeriodMinutes": 10,
                "scopedMode": false
            }
        },
        "nodeTemplatesPartialMatchingEnabled": false,
        "clusterLimits": {
            "cpu": {
                "maxCores": 20,
                "minCores": 1
            },
            "enabled": true
        }
    }
  EOT
}
```

New configuration:
```hcl
module "castai-aks-cluster" {
  autoscaler_settings = {
    enabled                                 = true
    node_templates_partial_matching_enabled = false

    unschedulable_pods = {
      enabled = true
    }

    node_downscaler = {
      enabled = true

      empty_nodes = {
        enabled = true
      }

      evictor = {
        aggressive_mode           = false
        cycle_interval            = "5m10s"
        dry_run                   = false
        enabled                   = true
        node_grace_period_minutes = 10
        scoped_mode               = false
      }
    }

    cluster_limits = {
      enabled = true

      cpu = {
        max_cores = 20
        min_cores = 1
      }
    }
  }
}
```

Migrating from 9.x.x to 10.x.x
---------------------------

Version 10.x.x removes deprecated autoscaler fields that have been moved to node templates.

**Removed:**
* `autoscaler_policies_json` - Use `autoscaler_settings` instead
* `autoscaler_settings.unschedulable_pods.custom_instances_enabled` - No longer needed
* `autoscaler_settings.unschedulable_pods.headroom` - Use low-priority placeholder workloads instead
* `autoscaler_settings.unschedulable_pods.headroom_spot` - Use low-priority placeholder workloads instead
* `autoscaler_settings.unschedulable_pods.node_constraints` - Use `node_templates` constraints instead
* `autoscaler_settings.spot_instances` - Use `node_templates` constraints instead

**Migration guide:**

Old configuration:
```hcl
module "castai-aks-cluster" {
  source = "castai/aks/castai"

  autoscaler_settings = {
    enabled = true

    unschedulable_pods = {
      enabled                  = true
      custom_instances_enabled = true

      headroom = {
        enabled           = true
        cpu_percentage    = 10
        memory_percentage = 10
      }

      node_constraints = {
        min_cpu_cores = 4
        max_cpu_cores = 32
      }
    }

    spot_instances = {
      enabled = true
      spot_backups = {
        enabled = true
      }
    }
  }
}
```

New configuration:
```hcl
module "castai-aks-cluster" {
  source = "castai/aks/castai"

  autoscaler_settings = {
    enabled = true

    unschedulable_pods = {
      enabled = true
    }
  }

  node_templates = {
    default_by_castai = {
      configuration_id = module.castai-aks-cluster.castai_node_configurations["default"]
      is_default       = true

      constraints = {
        min_cpu            = 4
        max_cpu            = 32
        spot               = true
        use_spot_fallbacks = true
      }
    }
  }
}

# For headroom: Deploy low-priority placeholder workloads
# See: https://docs.cast.ai/docs/autoscaler-faq#how-can-i-maintain-cluster-headroom
```

**Key changes:**
* Node constraints (`min_cpu_cores`, `max_cpu_cores`, `min_ram_mib`, `max_ram_mib`) are now configured in `node_templates.constraints` as `min_cpu`, `max_cpu`, `min_memory`, `max_memory`
* Spot instance settings (`spot`, `use_spot_fallbacks`) are now configured in `node_templates.constraints`
* The default node template is named `default_by_castai`
* For headroom functionality, deploy low-priority placeholder workloads as described in the [CAST AI documentation](https://docs.cast.ai/docs/autoscaler-faq#how-can-i-maintain-cluster-headroom)

# Examples 

Usage examples are located in [terraform provider repo](https://github.com/castai/terraform-provider-castai/tree/master/examples/aks)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 0.13 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | ~> 3 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 3.7.0 |
| <a name="requirement_castai"></a> [castai](#requirement\_castai) | >= 8.7 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | ~> 3 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 3.7.0 |
| <a name="provider_castai"></a> [castai](#provider\_castai) | >= 8.7 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.0.0 |
| <a name="provider_null"></a> [null](#provider\_null) | ~> 3 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_castai_omni_cluster"></a> [castai\_omni\_cluster](#module\_castai\_omni\_cluster) | castai/omni-cluster/castai | ~> 2.0 |

## Resources

| Name | Type |
|------|------|
| [azuread_application.castai](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application_password.castai](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_password) | resource |
| [azuread_service_principal.castai](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/service_principal) | resource |
| [azurerm_federated_identity_credential.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_role_assignment.castai_additional_resource_groups](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.castai_node_resource_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.castai_resource_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_definition.castai](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_definition) | resource |
| [azurerm_user_assigned_identity.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [castai_aks_cluster.castai_cluster](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/aks_cluster) | resource |
| [castai_autoscaler.castai_autoscaler_policies](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/autoscaler) | resource |
| [castai_node_configuration.this](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/node_configuration) | resource |
| [castai_node_configuration_default.this](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/node_configuration_default) | resource |
| [castai_node_template.this](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/node_template) | resource |
| [castai_workload_scaling_policy.this](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/workload_scaling_policy) | resource |
| [helm_release.castai_agent](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_ai_optimizer_proxy](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_ai_optimizer_proxy_self_managed](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_cluster_controller](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_cluster_controller_self_managed](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_evictor](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_evictor_ext](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_evictor_self_managed](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_kvisor](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_kvisor_self_managed](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_pod_mutator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_pod_mutator_self_managed](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_pod_pinner](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_pod_pinner_self_managed](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_spot_handler](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_workload_autoscaler](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.castai_workload_autoscaler_self_managed](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [null_resource.wait_for_cluster](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [azuread_client_config.current](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/client_config) | data source |
| [azurerm_kubernetes_cluster.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/kubernetes_cluster) | data source |
| [azurerm_kubernetes_cluster.castai](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/kubernetes_cluster) | data source |
| [castai_impersonation_service_account.this](https://registry.terraform.io/providers/castai/castai/latest/docs/data-sources/impersonation_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_resource_groups"></a> [additional\_resource\_groups](#input\_additional\_resource\_groups) | n/a | `list(string)` | `[]` | no |
| <a name="input_agent_values"></a> [agent\_values](#input\_agent\_values) | List of YAML formatted string values for agent helm chart | `list(string)` | `[]` | no |
| <a name="input_agent_version"></a> [agent\_version](#input\_agent\_version) | Version of castai-agent helm chart. If not provided, latest version will be used. | `string` | `null` | no |
| <a name="input_ai_optimizer_values"></a> [ai\_optimizer\_values](#input\_ai\_optimizer\_values) | List of YAML formatted string with ai-optimizer values | `list(string)` | `[]` | no |
| <a name="input_ai_optimizer_version"></a> [ai\_optimizer\_version](#input\_ai\_optimizer\_version) | Version of castai-ai-optimizer helm chart. Default latest | `string` | `null` | no |
| <a name="input_aks_cluster_name"></a> [aks\_cluster\_name](#input\_aks\_cluster\_name) | Name of the cluster to be connected to CAST AI. | `string` | n/a | yes |
| <a name="input_aks_cluster_region"></a> [aks\_cluster\_region](#input\_aks\_cluster\_region) | Region of the AKS cluster | `string` | n/a | yes |
| <a name="input_api_url"></a> [api\_url](#input\_api\_url) | URL of alternative CAST AI API to be used during development or testing | `string` | `"https://api.cast.ai"` | no |
| <a name="input_authentication_method"></a> [authentication\_method](#input\_authentication\_method) | Authentication method for CAST AI. Use 'client\_secret' for service principal with password, or 'workload\_identity' for federated identity credential | `string` | `"client_secret"` | no |
| <a name="input_autoscaler_settings"></a> [autoscaler\_settings](#input\_autoscaler\_settings) | Optional Autoscaler policy definitions to override current autoscaler settings | `any` | `null` | no |
| <a name="input_azuread_owners"></a> [azuread\_owners](#input\_azuread\_owners) | A set of object IDs of principals that will be granted ownership of the Azure AD service principal and application. Defaults to current user. | `list(string)` | `null` | no |
| <a name="input_castai_api_token"></a> [castai\_api\_token](#input\_castai\_api\_token) | Optional CAST AI API token created in console.cast.ai API Access keys section. Used only when `wait_for_cluster_ready` is set to true | `string` | `""` | no |
| <a name="input_castai_components_labels"></a> [castai\_components\_labels](#input\_castai\_components\_labels) | Optional additional Kubernetes labels for CAST AI pods | `map(any)` | `{}` | no |
| <a name="input_castai_components_sets"></a> [castai\_components\_sets](#input\_castai\_components\_sets) | Optional additional 'set' configurations for every CAST AI Helm release. | `map(string)` | `{}` | no |
| <a name="input_cluster_controller_values"></a> [cluster\_controller\_values](#input\_cluster\_controller\_values) | List of YAML formatted string values for cluster-controller helm chart | `list(string)` | `[]` | no |
| <a name="input_cluster_controller_version"></a> [cluster\_controller\_version](#input\_cluster\_controller\_version) | Version of castai-cluster-controller helm chart. If not provided, latest version will be used. | `string` | `null` | no |
| <a name="input_default_node_configuration"></a> [default\_node\_configuration](#input\_default\_node\_configuration) | ID of the default node configuration | `string` | `""` | no |
| <a name="input_default_node_configuration_name"></a> [default\_node\_configuration\_name](#input\_default\_node\_configuration\_name) | Name of the default node configuration | `string` | `""` | no |
| <a name="input_delete_nodes_on_disconnect"></a> [delete\_nodes\_on\_disconnect](#input\_delete\_nodes\_on\_disconnect) | Optionally delete Cast AI created nodes when the cluster is destroyed | `bool` | `false` | no |
| <a name="input_evictor_ext_values"></a> [evictor\_ext\_values](#input\_evictor\_ext\_values) | List of YAML formatted string with evictor-ext values | `list(string)` | `[]` | no |
| <a name="input_evictor_ext_version"></a> [evictor\_ext\_version](#input\_evictor\_ext\_version) | Version of castai-evictor-ext chart. Default latest | `string` | `null` | no |
| <a name="input_evictor_values"></a> [evictor\_values](#input\_evictor\_values) | List of YAML formatted string values for evictor helm chart | `list(string)` | `[]` | no |
| <a name="input_evictor_version"></a> [evictor\_version](#input\_evictor\_version) | Version of castai-evictor chart. If not provided, latest version will be used. | `string` | `null` | no |
| <a name="input_grpc_url"></a> [grpc\_url](#input\_grpc\_url) | gRPC endpoint used by pod-pinner | `string` | `"grpc.cast.ai:443"` | no |
| <a name="input_http_proxy"></a> [http\_proxy](#input\_http\_proxy) | Address to use for proxying http requests from CAST AI components running directly on nodes. | `string` | `null` | no |
| <a name="input_https_proxy"></a> [https\_proxy](#input\_https\_proxy) | Address to use for proxying https requests from CAST AI components running directly on nodes. | `string` | `null` | no |
| <a name="input_install_ai_optimizer"></a> [install\_ai\_optimizer](#input\_install\_ai\_optimizer) | Optional flag for installation of AI Optimizer (https://docs.cast.ai/docs/getting-started-ai) | `bool` | `false` | no |
| <a name="input_install_omni"></a> [install\_omni](#input\_install\_omni) | Optional flag for installing Omni capability | `bool` | `false` | no |
| <a name="input_install_pod_mutator"></a> [install\_pod\_mutator](#input\_install\_pod\_mutator) | Optional flag for installation of pod mutator | `bool` | `false` | no |
| <a name="input_install_security_agent"></a> [install\_security\_agent](#input\_install\_security\_agent) | Optional flag for installation of security agent (Kvisor - https://docs.cast.ai/docs/kvisor) | `bool` | `false` | no |
| <a name="input_install_workload_autoscaler"></a> [install\_workload\_autoscaler](#input\_install\_workload\_autoscaler) | Optional flag for installation of workload autoscaler (https://docs.cast.ai/docs/workload-autoscaling-configuration) | `bool` | `false` | no |
| <a name="input_kvisor_controller_extra_args"></a> [kvisor\_controller\_extra\_args](#input\_kvisor\_controller\_extra\_args) | ⚠️ DEPRECATED: use kvisor\_values instead (see example: https://github.com/castai/terraform-provider-castai/tree/master/examples/aks/aks_cluster_with_security/castai.tf ). Extra arguments for the kvisor controller. Optionally enable kvisor to lint Kubernetes YAML manifests, scan workload images and check if workloads pass CIS Kubernetes Benchmarks as well as NSA, WASP and PCI recommendations. | `map(string)` | <pre>{<br/>  "image-scan-enabled": "true",<br/>  "kube-bench-enabled": "true",<br/>  "kube-linter-enabled": "true"<br/>}</pre> | no |
| <a name="input_kvisor_grpc_addr"></a> [kvisor\_grpc\_addr](#input\_kvisor\_grpc\_addr) | CAST AI Kvisor optimized GRPC API address | `string` | `"kvisor.prod-master.cast.ai:443"` | no |
| <a name="input_kvisor_values"></a> [kvisor\_values](#input\_kvisor\_values) | List of YAML formatted string values for kvisor helm chart, see example: https://github.com/castai/terraform-provider-castai/tree/master/examples/aks/aks_cluster_with_security/castai.tf | `list(string)` | `[]` | no |
| <a name="input_kvisor_version"></a> [kvisor\_version](#input\_kvisor\_version) | Version of kvisor chart. If not provided, latest version will be used. | `string` | `null` | no |
| <a name="input_kvisor_wait"></a> [kvisor\_wait](#input\_kvisor\_wait) | Wait for kvisor chart to finish release | `bool` | `true` | no |
| <a name="input_no_proxy"></a> [no\_proxy](#input\_no\_proxy) | List of addresses to skip proxying requests from CAST AI components running directly on nodes. Used with http\_proxy and https\_proxy. | `list(string)` | `[]` | no |
| <a name="input_node_configurations"></a> [node\_configurations](#input\_node\_configurations) | Map of AKS node configurations to create | `any` | `{}` | no |
| <a name="input_node_resource_group"></a> [node\_resource\_group](#input\_node\_resource\_group) | n/a | `string` | n/a | yes |
| <a name="input_node_templates"></a> [node\_templates](#input\_node\_templates) | Map of node templates to create | `any` | `{}` | no |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | DEPRECATED (required only for pod mutator v0.0.25 and older): CAST AI Organization ID | `string` | `""` | no |
| <a name="input_pod_mutator_values"></a> [pod\_mutator\_values](#input\_pod\_mutator\_values) | List of YAML formatted string values for pod-mutator helm chart | `list(string)` | `[]` | no |
| <a name="input_pod_mutator_version"></a> [pod\_mutator\_version](#input\_pod\_mutator\_version) | Version of castai-pod-mutator helm chart. Default latest | `string` | `null` | no |
| <a name="input_pod_pinner_values"></a> [pod\_pinner\_values](#input\_pod\_pinner\_values) | List of YAML formatted string values for agent helm chart | `list(string)` | `[]` | no |
| <a name="input_pod_pinner_version"></a> [pod\_pinner\_version](#input\_pod\_pinner\_version) | Version of pod-pinner helm chart. Default latest | `string` | `null` | no |
| <a name="input_resource_group"></a> [resource\_group](#input\_resource\_group) | n/a | `string` | n/a | yes |
| <a name="input_self_managed"></a> [self\_managed](#input\_self\_managed) | Whether CAST AI components' upgrades are managed by a customer; by default upgrades are managed CAST AI central system. WARNING: changing this after the module was created is not supported. | `bool` | `false` | no |
| <a name="input_spot_handler_values"></a> [spot\_handler\_values](#input\_spot\_handler\_values) | List of YAML formatted string values for spot-handler helm chart | `list(string)` | `[]` | no |
| <a name="input_spot_handler_version"></a> [spot\_handler\_version](#input\_spot\_handler\_version) | Version of castai-spot-handler helm chart. If not provided, latest version will be used. | `string` | `null` | no |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Azure subscription ID | `string` | n/a | yes |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | n/a | `string` | n/a | yes |
| <a name="input_wait_for_cluster_ready"></a> [wait\_for\_cluster\_ready](#input\_wait\_for\_cluster\_ready) | Wait for cluster to be ready before finishing the module execution, this option requires `castai_api_token` to be set | `bool` | `false` | no |
| <a name="input_workload_autoscaler_values"></a> [workload\_autoscaler\_values](#input\_workload\_autoscaler\_values) | List of YAML formatted string with cluster-workload-autoscaler values | `list(string)` | `[]` | no |
| <a name="input_workload_autoscaler_version"></a> [workload\_autoscaler\_version](#input\_workload\_autoscaler\_version) | Version of castai-workload-autoscaler helm chart. Default latest | `string` | `null` | no |
| <a name="input_workload_scaling_policies"></a> [workload\_scaling\_policies](#input\_workload\_scaling\_policies) | Map of workload scaling policies to create | `any` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_castai_node_configurations"></a> [castai\_node\_configurations](#output\_castai\_node\_configurations) | Map of node configurations ids by name |
| <a name="output_castai_node_templates"></a> [castai\_node\_templates](#output\_castai\_node\_templates) | Map of node template by name |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | CAST.AI cluster id, which can be used for accessing cluster data using API |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | CAST.AI organization id of the cluster |
<!-- END_TF_DOCS -->
