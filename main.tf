locals {
  configuration_id_regex_pattern = "[a-zA-Z0-9]{8}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{12}"
}

resource "castai_aks_cluster" "castai_cluster" {
  name = var.aks_cluster_name

  region          = var.aks_cluster_region
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = azuread_application.castai.client_id
  client_secret   = azuread_application_password.castai.value

  node_resource_group        = var.node_resource_group
  delete_nodes_on_disconnect = var.delete_nodes_on_disconnect

  # CastAI needs cloud permission to do some clean up
  # when disconnecting the cluster.
  # This ensures IAM configurations exist during disconnect.
  depends_on = [
    azurerm_role_definition.castai,
    azurerm_role_assignment.castai_resource_group,
    azurerm_role_assignment.castai_node_resource_group,
    azurerm_role_assignment.castai_additional_resource_groups,
    azuread_application.castai,
    azuread_application_password.castai,
    azuread_service_principal.castai
  ]
}

resource "castai_node_configuration" "this" {
  for_each = { for k, v in var.node_configurations : k => v }

  cluster_id = castai_aks_cluster.castai_cluster.id

  name              = try(each.value.name, each.key)
  disk_cpu_ratio    = try(each.value.disk_cpu_ratio, 0)
  drain_timeout_sec = try(each.value.drain_timeout_sec, 0)
  min_disk_size     = try(each.value.min_disk_size, 100)
  subnets           = try(each.value.subnets, null)
  ssh_public_key    = try(each.value.ssh_public_key, null)
  image             = try(each.value.image, null)
  tags              = try(each.value.tags, {})

  aks {
    max_pods_per_node = try(each.value.max_pods_per_node, 30)
    os_disk_type      = try(each.value.os_disk_type, null)
  }
}

resource "castai_node_configuration_default" "this" {
  cluster_id       = castai_aks_cluster.castai_cluster.id
  configuration_id = var.default_node_configuration_name != "" ? castai_node_configuration.this[var.default_node_configuration_name].id :  length(regexall(local.configuration_id_regex_pattern, var.default_node_configuration)) > 0 ? var.default_node_configuration : castai_node_configuration.this[var.default_node_configuration].id

  depends_on = [castai_node_configuration.this]
}

resource "castai_node_template" "this" {
  for_each = { for k, v in var.node_templates : k => v }

  cluster_id = castai_aks_cluster.castai_cluster.id

  name                         = try(each.value.name, each.key)
  is_default                   = try(each.value.is_default, false)
  is_enabled                   = try(each.value.is_enabled, true)
  configuration_id             = try(each.value.configuration_name, null) != null ? castai_node_configuration.this[each.value.configuration_name].id : can(each.value.configuration_id) ? length(regexall(local.configuration_id_regex_pattern, each.value.configuration_id)) > 0 ? each.value.configuration_id : castai_node_configuration.this[each.value.configuration_id].id : null
  should_taint                 = try(each.value.should_taint, true)
  rebalancing_config_min_nodes = try(each.value.rebalancing_config_min_nodes, 0)

  custom_labels = try(each.value.custom_labels, {})

  dynamic "custom_taints" {
    for_each = flatten([lookup(each.value, "custom_taints", [])])

    content {
      key    = try(custom_taints.value.key, null)
      value  = try(custom_taints.value.value, null)
      effect = try(custom_taints.value.effect, null)
    }
  }

  dynamic "constraints" {
    for_each = [for constraints in flatten([lookup(each.value, "constraints", [])]) : constraints if constraints != null]

    content {
      compute_optimized                           = try(constraints.value.compute_optimized, null)
      storage_optimized                           = try(constraints.value.storage_optimized, null)
      compute_optimized_state                    = try(constraints.value.compute_optimized_state, "")
      storage_optimized_state                    = try(constraints.value.storage_optimized_state, "")
      spot                                        = try(constraints.value.spot, false)
      on_demand                                   = try(constraints.value.on_demand, null)
      use_spot_fallbacks                          = try(constraints.value.use_spot_fallbacks, false)
      fallback_restore_rate_seconds               = try(constraints.value.fallback_restore_rate_seconds, null)
      enable_spot_diversity                       = try(constraints.value.enable_spot_diversity, false)
      spot_diversity_price_increase_limit_percent = try(constraints.value.spot_diversity_price_increase_limit_percent, null)
      spot_interruption_predictions_enabled       = try(constraints.value.spot_interruption_predictions_enabled, false)
      spot_interruption_predictions_type          = try(constraints.value.spot_interruption_predictions_type, null)
      min_cpu                                     = try(constraints.value.min_cpu, null)
      max_cpu                                     = try(constraints.value.max_cpu, null)
      min_memory                                  = try(constraints.value.min_memory, null)
      max_memory                                  = try(constraints.value.max_memory, null)
      architectures                               = try(constraints.value.architectures, ["amd64"])
      os                                          = try(constraints.value.os, ["linux"])
      azs                                         = try(constraints.value.azs, null)
      burstable_instances                         = try(constraints.value.burstable_instances, null)
      customer_specific                           = try(constraints.value.customer_specific, null)
      cpu_manufacturers                           = try(constraints.value.cpu_manufacturers, null)

      dynamic "instance_families" {
        for_each = [for instance_families in flatten([lookup(constraints.value, "instance_families", [])]) : instance_families if instance_families != null]

        content {
          include = try(instance_families.value.include, [])
          exclude = try(instance_families.value.exclude, [])
        }
      }

      dynamic "custom_priority" {
        for_each = [for custom_priority in flatten([lookup(constraints.value, "custom_priority", [])]) : custom_priority if custom_priority != null]

        content {
          instance_families = try(custom_priority.value.instance_families, [])
          spot              = try(custom_priority.value.spot, false)
          on_demand         = try(custom_priority.value.on_demand, false)
        }
      }
    }
  }
  depends_on = [castai_autoscaler.castai_autoscaler_policies]
}

resource "castai_workload_scaling_policy" "this" {
  for_each = { for k, v in var.workload_scaling_policies : k => v }

  name              = try(each.value.name, each.key)
  cluster_id        = castai_aks_cluster.castai_cluster.id

  apply_type        = try(each.value.apply_type, "DEFERRED")
  management_option = try(each.value.management_option, "READ_ONLY")
  cpu {
    function        = try(each.value.cpu.function, "QUANTILE")
    overhead        = try(each.value.cpu.overhead, 0)
    apply_threshold = try(each.value.cpu.apply_threshold, 0.1)
    args            = try(each.value.cpu.args, ["0.8"])
  }
  memory {
    function        = try(each.value.memory.function, "MAX")
    overhead        = try(each.value.memory.overhead, 0.1)
    apply_threshold = try(each.value.memory.apply_threshold, 0.1)
  }
}

resource "helm_release" "castai_agent" {
  name             = "castai-agent"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-agent"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.agent_version
  values  = var.agent_values

  set {
    name  = "replicaCount"
    value = "2"
  }
  set {
    name  = "provider"
    value = "aks"
  }

  set {
    name  = "createNamespace"
    value = "false"
  }

  dynamic "set" {
    for_each = var.api_url != "" ? [var.api_url] : []
    content {
      name  = "apiURL"
      value = var.api_url
    }
  }

  dynamic "set" {
    for_each = var.castai_components_labels
    content {
      name  = "podLabels.${set.key}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.castai_components_sets
    content {
      name  = set.key
      value = set.value
    }
  }

  set_sensitive {
    name  = "apiKey"
    value = castai_aks_cluster.castai_cluster.cluster_token
  }
}

resource "helm_release" "castai_cluster_controller" {
  count = var.self_managed ? 0 : 1

  name             = "cluster-controller"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-cluster-controller"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.cluster_controller_version
  values  = var.cluster_controller_values

  set {
    name  = "aks.enabled"
    value = "true"
  }

  set {
    name  = "castai.clusterID"
    value = castai_aks_cluster.castai_cluster.id
  }

  dynamic "set" {
    for_each = var.api_url != "" ? [var.api_url] : []
    content {
      name  = "castai.apiURL"
      value = var.api_url
    }
  }

  dynamic "set" {
    for_each = var.castai_components_labels
    content {
      name  = "podLabels.${set.key}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.castai_components_sets
    content {
      name  = set.key
      value = set.value
    }
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_aks_cluster.castai_cluster.cluster_token
  }

  depends_on = [helm_release.castai_agent]

  lifecycle {
    ignore_changes = [version]
  }
}

resource "helm_release" "castai_cluster_controller_self_managed" {
  count = var.self_managed ? 1 : 0

  name             = "cluster-controller"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-cluster-controller"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.cluster_controller_version
  values  = var.cluster_controller_values

  set {
    name  = "aks.enabled"
    value = "true"
  }

  set {
    name  = "castai.clusterID"
    value = castai_aks_cluster.castai_cluster.id
  }

  dynamic "set" {
    for_each = var.api_url != "" ? [var.api_url] : []
    content {
      name  = "castai.apiURL"
      value = var.api_url
    }
  }

  dynamic "set" {
    for_each = var.castai_components_labels
    content {
      name  = "podLabels.${set.key}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.castai_components_sets
    content {
      name  = set.key
      value = set.value
    }
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_aks_cluster.castai_cluster.cluster_token
  }

  depends_on = [helm_release.castai_agent]
}

resource "null_resource" "wait_for_cluster" {
  count      = var.wait_for_cluster_ready ? 1 : 0
  depends_on = [helm_release.castai_cluster_controller, helm_release.castai_agent]

  provisioner "local-exec" {
    environment = {
      API_KEY = var.castai_api_token
    }
    command = <<-EOT
        RETRY_COUNT=30
        POOLING_INTERVAL=30

        for i in $(seq 1 $RETRY_COUNT); do
            sleep $POOLING_INTERVAL
            curl -s ${var.api_url}/v1/kubernetes/external-clusters/${castai_aks_cluster.castai_cluster.id} -H "x-api-key: $API_KEY" | grep '"status"\s*:\s*"ready"' && exit 0
        done

        echo "Cluster is not ready after 15 minutes"
        exit 1
    EOT

    interpreter = ["bash", "-c"]
  }
}

resource "helm_release" "castai_evictor" {
  count = var.self_managed ? 0 : 1

  name             = "castai-evictor"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-evictor"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.evictor_version
  values  = var.evictor_values

  set {
    name  = "replicaCount"
    value = "0"
  }

  set {
    name  = "castai-evictor-ext.enabled"
    value = "false"
  }

  dynamic "set" {
    for_each = var.castai_components_labels
    content {
      name  = "podLabels.${set.key}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.castai_components_sets
    content {
      name  = set.key
      value = set.value
    }
  }

  depends_on = [helm_release.castai_agent]

  lifecycle {
    ignore_changes = [set, version]
  }
}

resource "helm_release" "castai_evictor_self_managed" {
  count = var.self_managed ? 1 : 0

  name             = "castai-evictor"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-evictor"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.evictor_version
  values  = var.evictor_values

  set {
    name  = "castai-evictor-ext.enabled"
    value = "false"
  }

  dynamic "set" {
    for_each = var.castai_components_labels
    content {
      name  = "podLabels.${set.key}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.castai_components_sets
    content {
      name  = set.key
      value = set.value
    }
  }

  depends_on = [helm_release.castai_agent]
}

resource "helm_release" "castai_evictor_ext" {
  name             = "castai-evictor-ext"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-evictor-ext"
  namespace        = "castai-agent"
  create_namespace = false
  cleanup_on_fail  = true
  wait             = true

  version = var.evictor_ext_version
  values  = var.evictor_ext_values

  depends_on = [helm_release.castai_evictor]
}

resource "helm_release" "castai_pod_pinner" {
  count = var.self_managed ? 0 : 1

  name             = "castai-pod-pinner"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-pod-pinner"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.pod_pinner_version
  values  = var.pod_pinner_values

  set {
    name  = "castai.clusterID"
    value = castai_aks_cluster.castai_cluster.id
  }

  dynamic "set" {
    for_each = var.api_url != "" ? [var.api_url] : []
    content {
      name  = "castai.apiURL"
      value = var.api_url
    }
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_aks_cluster.castai_cluster.cluster_token
  }

  dynamic "set" {
    for_each = var.grpc_url != "" ? [var.grpc_url] : []
    content {
      name  = "castai.grpcURL"
      value = var.grpc_url
    }
  }

  dynamic "set" {
    for_each = var.castai_components_labels
    content {
      name  = "podLabels.${set.key}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.castai_components_sets
    content {
      name  = set.key
      value = set.value
    }
  }

  set {
    name  = "replicaCount"
    value = "0"
  }

  depends_on = [helm_release.castai_agent]

  lifecycle {
    ignore_changes = [set, version]
  }
}

resource "helm_release" "castai_pod_pinner_self_managed" {
  count = var.self_managed ? 1 : 0

  name             = "castai-pod-pinner"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-pod-pinner"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.pod_pinner_version
  values  = var.pod_pinner_values

  set {
    name  = "castai.clusterID"
    value = castai_aks_cluster.castai_cluster.id
  }

  dynamic "set" {
    for_each = var.api_url != "" ? [var.api_url] : []
    content {
      name  = "castai.apiURL"
      value = var.api_url
    }
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_aks_cluster.castai_cluster.cluster_token
  }

  dynamic "set" {
    for_each = var.grpc_url != "" ? [var.grpc_url] : []
    content {
      name  = "castai.grpcURL"
      value = var.grpc_url
    }
  }

  dynamic "set" {
    for_each = var.castai_components_labels
    content {
      name  = "podLabels.${set.key}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.castai_components_sets
    content {
      name  = set.key
      value = set.value
    }
  }

  depends_on = [helm_release.castai_agent]
}

resource "helm_release" "castai_spot_handler" {
  name             = "castai-spot-handler"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-spot-handler"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.spot_handler_version
  values  = var.spot_handler_values

  set {
    name  = "castai.provider"
    value = "azure"
  }

  set {
    name  = "createNamespace"
    value = "false"
  }

  dynamic "set" {
    for_each = var.api_url != "" ? [var.api_url] : []
    content {
      name  = "castai.apiURL"
      value = var.api_url
    }
  }

  dynamic "set" {
    for_each = var.castai_components_labels
    content {
      name  = "podLabels.${set.key}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.castai_components_sets
    content {
      name  = set.key
      value = set.value
    }
  }

  set {
    name  = "castai.clusterID"
    value = castai_aks_cluster.castai_cluster.id
  }

  depends_on = [helm_release.castai_agent]
}

resource "helm_release" "castai_kvisor" {
  count = var.install_security_agent && !var.self_managed ? 1 : 0

  name             = "castai-kvisor"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-kvisor"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  version = var.kvisor_version
  values  = var.kvisor_values

  lifecycle {
    ignore_changes = [version]
  }

  set {
    name  = "castai.clusterID"
    value = castai_aks_cluster.castai_cluster.id
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_aks_cluster.castai_cluster.cluster_token
  }

  set {
    name  = "castai.grpcAddr"
    value = var.api_grpc_addr
  }

  dynamic "set" {
    for_each = var.kvisor_controller_extra_args
    content {
      name  = "controller.extraArgs.${set.key}"
      value = set.value
    }
  }

  set {
    name  = "controller.extraArgs.kube-bench-cloud-provider"
    value = "aks"
  }

  dynamic "set" {
    for_each = var.castai_components_sets
    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "castai_kvisor_self_managed" {
  count = var.install_security_agent && var.self_managed ? 1 : 0

  name             = "castai-kvisor"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-kvisor"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  version = var.kvisor_version
  values  = var.kvisor_values

  set {
    name  = "castai.clusterID"
    value = castai_aks_cluster.castai_cluster.id
  }

  set_sensitive {
    name  = "castai.apiKey"
    value = castai_aks_cluster.castai_cluster.cluster_token
  }

  set {
    name  = "castai.grpcAddr"
    value = var.api_grpc_addr
  }

  dynamic "set" {
    for_each = var.kvisor_controller_extra_args
    content {
      name  = "controller.extraArgs.${set.key}"
      value = set.value
    }
  }

  set {
    name  = "controller.extraArgs.kube-bench-cloud-provider"
    value = "aks"
  }

  dynamic "set" {
    for_each = var.castai_components_sets
    content {
      name  = set.key
      value = set.value
    }
  }
}

#---------------------------------------------------#
# CAST.AI Workload Autoscaler configuration         #
#---------------------------------------------------#
resource "helm_release" "castai_workload_autoscaler" {
  count = var.install_workload_autoscaler && !var.self_managed ? 1 : 0

  name             = "castai-workload-autoscaler"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-workload-autoscaler"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.workload_autoscaler_version
  values  = var.workload_autoscaler_values

  set {
    name  = "castai.apiKeySecretRef"
    value = "castai-cluster-controller"
  }

  set {
    name  = "castai.configMapRef"
    value = "castai-cluster-controller"
  }

  depends_on = [helm_release.castai_agent, helm_release.castai_cluster_controller]

  lifecycle {
    ignore_changes = [version]
  }
}

resource "helm_release" "castai_workload_autoscaler_self_managed" {
  count = var.install_workload_autoscaler && var.self_managed ? 1 : 0

  name             = "castai-workload-autoscaler"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-workload-autoscaler"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

  version = var.workload_autoscaler_version
  values  = var.workload_autoscaler_values

  set {
    name  = "castai.apiKeySecretRef"
    value = "castai-cluster-controller"
  }

  set {
    name  = "castai.configMapRef"
    value = "castai-cluster-controller"
  }

  depends_on = [helm_release.castai_agent, helm_release.castai_cluster_controller]
}

resource "castai_autoscaler" "castai_autoscaler_policies" {
  cluster_id               = castai_aks_cluster.castai_cluster.id

  // Deprecated  -- kept for backward compatibility
  autoscaler_policies_json = var.autoscaler_policies_json

  dynamic "autoscaler_settings" {
    for_each = var.autoscaler_settings != null ? [var.autoscaler_settings] : []

    content {
      enabled                                 = try(autoscaler_settings.value.enabled, null)
      is_scoped_mode                          = try(autoscaler_settings.value.is_scoped_mode, null)
      node_templates_partial_matching_enabled = try(autoscaler_settings.value.node_templates_partial_matching_enabled, null)

      dynamic "unschedulable_pods" {
        for_each = try([autoscaler_settings.value.unschedulable_pods], [])

        content {
          enabled                  = try(unschedulable_pods.value.enabled, null)
          custom_instances_enabled = try(unschedulable_pods.value.custom_instances_enabled, null)

          dynamic "headroom" {
            for_each = try([unschedulable_pods.value.headroom], [])

            content {
              enabled           = try(headroom.value.enabled, null)
              cpu_percentage    = try(headroom.value.cpu_percentage, null)
              memory_percentage = try(headroom.value.memory_percentage, null)
            }
          }

          dynamic "headroom_spot" {
            for_each = try([unschedulable_pods.value.headroom_spot], [])

            content {
              enabled           = try(headroom_spot.value.enabled, null)
              cpu_percentage    = try(headroom_spot.value.cpu_percentage, null)
              memory_percentage = try(headroom_spot.value.memory_percentage, null)
            }
          }

          dynamic "node_constraints" {
            for_each = try([unschedulable_pods.value.node_constraints], [])

            content {
              enabled       = try(node_constraints.value.enabled, null)
              min_cpu_cores = try(node_constraints.value.min_cpu_cores, null)
              max_cpu_cores = try(node_constraints.value.max_cpu_cores, null)
              min_ram_mib   = try(node_constraints.value.min_ram_mib, null)
              max_ram_mib   = try(node_constraints.value.max_ram_mib, null)
            }
          }
        }
      }

      dynamic "cluster_limits" {
        for_each = try([autoscaler_settings.value.cluster_limits], [])

        content {
          enabled = try(cluster_limits.value.enabled, null)


          dynamic "cpu" {
            for_each = try([cluster_limits.value.cpu], [])

            content {
              min_cores = try(cpu.value.min_cores, null)
              max_cores = try(cpu.value.max_cores, null)
            }
          }
        }
      }

      dynamic "spot_instances" {
        for_each = try([autoscaler_settings.value.spot_instances], [])

        content {
          enabled                             = try(spot_instances.value.enabled, null)
          max_reclaim_rate                    = try(spot_instances.value.max_reclaim_rate, null)
          spot_diversity_enabled              = try(spot_instances.value.spot_diversity_enabled, null)
          spot_diversity_price_increase_limit = try(spot_instances.value.spot_diversity_price_increase_limit, null)

          dynamic "spot_backups" {
            for_each = try([spot_instances.value.spot_backups], [])

            content {
              enabled                          = try(spot_backups.value.enabled, null)
              spot_backup_restore_rate_seconds = try(spot_backups.value.spot_backup_restore_rate_seconds, null)
            }
          }

          dynamic "spot_interruption_predictions" {
            for_each = try([spot_instances.value.spot_interruption_predictions], [])

            content {
              enabled                            = try(spot_interruption_predictions.value.enabled, null)
              spot_interruption_predictions_type = try(spot_interruption_predictions.value.spot_interruption_predictions_type, null)
            }
          }
        }
      }

      dynamic "node_downscaler" {
        for_each = try([autoscaler_settings.value.node_downscaler], [])

        content {
          enabled = try(node_downscaler.value.enabled, null)

          dynamic "empty_nodes" {
            for_each = try([node_downscaler.value.empty_nodes], [])

            content {
              enabled       = try(empty_nodes.value.enabled, null)
              delay_seconds = try(empty_nodes.value.delay_seconds, null)
            }
          }

          dynamic "evictor" {
            for_each = try([node_downscaler.value.evictor], [])

            content {
              enabled                                = try(evictor.value.enabled, null)
              dry_run                                = try(evictor.value.dry_run, null)
              aggressive_mode                        = try(evictor.value.aggressive_mode, null)
              scoped_mode                            = try(evictor.value.scoped_mode, null)
              cycle_interval                         = try(evictor.value.cycle_interval, null)
              node_grace_period_minutes              = try(evictor.value.node_grace_period_minutes, null)
              pod_eviction_failure_back_off_interval = try(evictor.value.pod_eviction_failure_back_off_interval, null)
              ignore_pod_disruption_budgets          = try(evictor.value.ignore_pod_disruption_budgets, null)
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.castai_agent, helm_release.castai_evictor]
}
