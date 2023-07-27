resource "castai_aks_cluster" "castai_cluster" {
  name = var.aks_cluster_name

  region          = var.aks_cluster_region
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = azuread_application.castai.application_id
  client_secret   = azuread_application_password.castai.value

  node_resource_group        = var.node_resource_group
  delete_nodes_on_disconnect = var.delete_nodes_on_disconnect

}

resource "castai_node_configuration" "this" {
  for_each = { for k, v in var.node_configurations : k => v }

  cluster_id = castai_aks_cluster.castai_cluster.id

  name           = try(each.value.name, each.key)
  disk_cpu_ratio = try(each.value.disk_cpu_ratio, 0)
  min_disk_size  = try(each.value.min_disk_size, 100)
  subnets        = try(each.value.subnets, null)
  ssh_public_key = try(each.value.ssh_public_key, null)
  image          = try(each.value.image, null)
  tags           = try(each.value.tags, {})

  aks {
    max_pods_per_node = try(each.value.max_pods_per_node, 30)
  }
}

resource "castai_node_configuration_default" "this" {
  cluster_id       = castai_aks_cluster.castai_cluster.id
  configuration_id = var.default_node_configuration
}

resource "castai_node_template" "this" {
  for_each = { for k, v in var.node_templates : k => v }

  cluster_id = castai_aks_cluster.castai_cluster.id

  name             = try(each.value.name, each.key)
  configuration_id = try(each.value.configuration_id, null)
  should_taint     = try(each.value.should_taint, true)

  dynamic "custom_label" {
    for_each = flatten([lookup(each.value, "custom_label", [])])

    content {
      key   = try(custom_label.value.key, null)
      value = try(custom_label.value.value, null)
    }
  }

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
      compute_optimized             = try(constraints.value.compute_optimized, false)
      storage_optimized             = try(constraints.value.storage_optimized, false)
      spot                          = try(constraints.value.spot, false)
      use_spot_fallbacks            = try(constraints.value.use_spot_fallbacks, false)
      fallback_restore_rate_seconds = try(constraints.value.fallback_restore_rate_seconds, null)
      min_cpu                       = try(constraints.value.min_cpu, null)
      max_cpu                       = try(constraints.value.max_cpu, null)
      min_memory                    = try(constraints.value.min_memory, null)
      max_memory                    = try(constraints.value.max_memory, null)

      dynamic "instance_families" {
        for_each = flatten([lookup(constraints.value, "instance_families", [])])

        content {
          include = try(instance_families.value.include, [])
          exclude = try(instance_families.value.exclude, [])
        }
      }
    }
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
  count = var.wait_for_cluster_ready ? 1 : 0
  depends_on = [helm_release.castai_cluster_controller, helm_release.castai_agent]

  provisioner "local-exec" {
    quiet = true
    environment = {
      API_KEY = var.castai_api_token
    }
    command = <<-EOT
        RETRY_COUNT=20
        POOLING_INTERVAL=30

        for i in $(seq 1 $RETRY_COUNT); do
            sleep $POOLING_INTERVAL
            curl -s ${var.api_url}/v1/kubernetes/external-clusters/${castai_gke_cluster.castai_cluster.id} -H "x-api-key: $API_KEY" | grep '"status"\s*:\s*"ready"' && exit 0
        done

        echo "Cluster is not ready after 10 minutes"
        exit 1
    EOT

    interpreter = ["bash", "-c"]
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

  set {
    name  = "castai.clusterID"
    value = castai_aks_cluster.castai_cluster.id
  }

  depends_on = [helm_release.castai_agent]
}

resource "helm_release" "castai_kvisor" {
  count = var.install_security_agent == true ? 1 : 0

  name             = "castai-kvisor"
  repository       = "https://castai.github.io/helm-charts"
  chart            = "castai-kvisor"
  namespace        = "castai-agent"
  create_namespace = true
  cleanup_on_fail  = true

  version = var.kvisor_version
  values  = var.kvisor_values

  set {
    name  = "castai.apiURL"
    value = var.api_url
  }

  set {
    name  = "castai.clusterID"
    value = castai_aks_cluster.castai_cluster.id
  }

  set {
    name  = "structuredConfig.provider"
    value = "aks"
  }
}

resource "castai_autoscaler" "castai_autoscaler_policies" {
  autoscaler_policies_json = var.autoscaler_policies_json
  cluster_id               = castai_aks_cluster.castai_cluster.id

  depends_on = [helm_release.castai_agent, helm_release.castai_evictor]
}
