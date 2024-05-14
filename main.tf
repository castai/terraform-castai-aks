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
  # when disconnecting the culster.
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
  configuration_id = length(regexall(local.configuration_id_regex_pattern, var.default_node_configuration)) > 0 ? var.default_node_configuration : castai_node_configuration.this[var.default_node_configuration].id

  depends_on = [castai_node_configuration.this]
}

resource "castai_node_template" "this" {
  for_each = { for k, v in var.node_templates : k => v }

  cluster_id = castai_aks_cluster.castai_cluster.id

  name                         = try(each.value.name, each.key)
  is_default                   = try(each.value.is_default, false)
  is_enabled                   = try(each.value.is_enabled, true)
  configuration_id             = can(each.value.configuration_id) ? length(regexall(local.configuration_id_regex_pattern, each.value.configuration_id)) > 0 ? each.value.configuration_id : castai_node_configuration.this[each.value.configuration_id].id : null
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
    for_each = flatten([lookup(each.value, "constraints", [])])
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

      dynamic "instance_families" {
        for_each = flatten([lookup(constraints.value, "instance_families", [])])

        content {
          include = try(instance_families.value.include, [])
          exclude = try(instance_families.value.exclude, [])
        }
      }

      dynamic "custom_priority" {
        for_each = flatten([lookup(constraints.value, "custom_priority", [])])

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

resource "helm_release" "castai_evictor" {
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

resource "helm_release" "castai_cluster_controller" {
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

resource "helm_release" "castai_pod_pinner" {
  name             = "castai-pod-pinner"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-pod-pinner"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true
  wait             = true

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
  count = var.install_security_agent ? 1 : 0

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

  set {
    name  = "controller.extraArgs.kube-linter-enabled"
    value = "true"
  }

  set {
    name  = "controller.extraArgs.image-scan-enabled"
    value = "true"
  }

  set {
    name  = "controller.extraArgs.kube-bench-enabled"
    value = "true"
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

resource "castai_autoscaler" "castai_autoscaler_policies" {
  autoscaler_policies_json = var.autoscaler_policies_json
  cluster_id               = castai_aks_cluster.castai_cluster.id

  depends_on = [helm_release.castai_agent, helm_release.castai_evictor]
}
