locals {
  # Common conditional non-sensitive values that we pass to helm_releases.
  # Set up as lists so they can be concatenated.
  set_apiurl = var.api_url != "" ? [{
    name  = "castai.apiURL"
    value = var.api_url
  }] : []
  set_cluster_id = [{
    name  = "castai.clusterID"
    value = castai_aks_cluster.castai_cluster.id
  }]
  set_organization_id = var.organization_id != "" ? [{
    name  = "castai.organizationID"
    value = var.organization_id
  }] : []
  set_grpc_url = var.grpc_url != "" ? [{
    name  = "castai.grpcURL"
    value = var.grpc_url
  }] : []
  set_kvisor_grpc_addr = var.kvisor_grpc_addr != "" ? [{
    name  = "castai.grpcAddr"
    value = var.kvisor_grpc_addr
  }] : []
  set_pod_labels = [for k, v in var.castai_components_labels : {
    name  = "podLabels.${k}"
    value = v
  }]
  set_components_sets = [for k, v in var.castai_components_sets : {
    name  = k
    value = v
  }]
  set_workload_autoscaler_keep_crds = var.workload_autoscaler_keep_crds ? [
    {
      name  = "crds.keep"
      value = true
    },
    {
      name  = "preDeleteHook.enabled"
      value = false
    },
  ] : []


  # Common conditional SENSITIVE values that we pass to helm_releases.
  # Set up as lists so they can be concatenated.
  set_sensitive_apikey = [{
    name  = "castai.apiKey"
    value = castai_aks_cluster.castai_cluster.cluster_token
  }]

  install_standalone_charts = !var.umbrella_enabled
  install_umbrella_chart    = var.umbrella_enabled

  # Inputs to the Cast AI Umbrella Helm release
  umbrella_set_castai_agent = [for s in concat(
    [
      {
        name  = "provider"
        value = "aks"
      },
      {
        name  = "replicaCount"
        value = "2"
      },
      {
        name  = "additionalEnv.STATIC_CLUSTER_ID"
        value = castai_aks_cluster.castai_cluster.id
      },
      {
        name  = "createNamespace"
        value = "false"
      },
    ],
    local.set_pod_labels,
    local.set_components_sets,
  ) : merge(s, { name = "autoscaler.castai-agent.${s.name}" })]

  umbrella_set_castai_cluster_controller = [for s in concat(
    [
      {
        name  = "aks.enabled"
        value = "true"
      },
    ],
    local.set_pod_labels,
    local.set_components_sets,
  ) : merge(s, { name = "autoscaler.castai-cluster-controller.${s.name}" })]

  umbrella_set_castai_pod_mutator = [for s in concat(
    [
      {
        name  = "enabled"
        value = var.install_pod_mutator
      },
    ],
    local.set_organization_id,
    local.set_pod_labels,
    local.set_components_sets,
  ) : merge(s, { name = "autoscaler.castai-pod-mutator.${s.name}" })]

  umbrella_set_castai_workload_autoscaler = [for s in concat(
    [
      {
        name  = "enabled"
        value = var.install_workload_autoscaler
      },
    ],
    local.set_components_sets,
  ) : merge(s, { name = "autoscaler.castai-workload-autoscaler.${s.name}" })]

  umbrella_set_castai_workload_autoscaler_exporter = [for s in concat(
    [
      {
        name  = "enabled"
        value = var.install_workload_autoscaler_exporter
      },
    ],
    local.set_components_sets,
  ) : merge(s, { name = "autoscaler.castai-workload-autoscaler-exporter.${s.name}" })]

  umbrella_set_castai_evictor = [for s in(var.self_managed ? concat(
    [
      {
        name  = "castai-evictor-ext.enabled"
        value = "true"
      },
      {
        name  = "managedByCASTAI"
        value = "false"
      },
    ],
    try(var.autoscaler_settings.node_downscaler.evictor.enabled, null) == false ? [
      {
        name  = "replicaCount"
        value = "0"
      },
    ] : [],
    local.set_pod_labels,
    local.set_components_sets,
    ) : concat(
    [
      {
        name  = "replicaCount"
        value = "0"
      },
      {
        name  = "castai-evictor-ext.enabled"
        value = "true"
      },
    ],
    local.set_pod_labels,
    local.set_components_sets,
  )) : merge(s, { name = "autoscaler.castai-evictor.${s.name}" })]

  umbrella_set_castai_pod_pinner = [for s in(var.self_managed ? concat(
    [
      {
        name  = "managedByCASTAI"
        value = "false"
      },
    ],
    local.set_pod_labels,
    local.set_components_sets,
    try(var.autoscaler_settings.unschedulable_pods.pod_pinner.enabled, null) == false ? [
      {
        name  = "replicaCount"
        value = "0"
      },
    ] : [],
    ) : concat(
    [
      {
        name  = "replicaCount"
        value = "0"
      },
    ],
    local.set_pod_labels,
    local.set_components_sets,
  )) : merge(s, { name = "autoscaler.castai-pod-pinner.${s.name}" })]

  umbrella_set_castai_spot_handler = [for s in concat(
    [
      {
        name  = "castai.provider"
        value = "azure"
      },
      {
        name  = "createNamespace"
        value = "false"
      },
    ],
    local.set_pod_labels,
    local.set_components_sets,
  ) : merge(s, { name = "autoscaler.castai-spot-handler.${s.name}" })]

  umbrella_set_castai_kvisor = [for s in concat(
    [
      {
        name  = "enabled"
        value = var.install_security_agent
      },
      {
        name  = "controller.extraArgs.kube-bench-cloud-provider"
        value = "aks"
      },
    ],
    local.set_kvisor_grpc_addr,
    local.set_components_sets,
    [for k, v in var.kvisor_controller_extra_args : {
      name  = "controller.extraArgs.${k}"
      value = v
    }],
  ) : merge(s, { name = "autoscaler.castai-kvisor.${s.name}" })]

  umbrella_set_castai_live = [for s in concat(
    [
      {
        name  = "enabled"
        value = var.install_live
      },
    ],
    local.set_components_sets,
  ) : merge(s, { name = "autoscaler.castai-live.${s.name}" })]

  # Each component's var.<chart>_values (list of YAML strings) re-nested under
  # autoscaler.<chart-name> so the umbrella chart applies them to the matching
  # subchart. Empty lists are skipped; multiple YAML documents per component are
  # merged.
  # evictor-ext values are nested one level deeper (castai-evictor.castai-evictor-ext)
  # so the umbrella chart applies them to the evictor's "ext" subchart, mirroring the
  # castai-evictor-ext.* set overrides below.
  umbrella_evictor_values_decoded = merge([for v in var.evictor_values : yamldecode(v)]...)
  umbrella_evictor_ext_values     = merge([for v in var.evictor_ext_values : yamldecode(v)]...)

  umbrella_evictor_values = merge(
    local.umbrella_evictor_values_decoded,
    length(var.evictor_ext_values) > 0 ? { "castai-evictor-ext" = local.umbrella_evictor_ext_values } : {}
  )

  umbrella_chart_values = {
    "castai-agent"                        = var.agent_values
    "castai-cluster-controller"           = var.cluster_controller_values
    "castai-pod-mutator"                  = var.pod_mutator_values
    "castai-workload-autoscaler"          = var.workload_autoscaler_values
    "castai-workload-autoscaler-exporter" = var.workload_autoscaler_exporter_values
    "castai-pod-pinner"                   = var.pod_pinner_values
    "castai-spot-handler"                 = var.spot_handler_values
    "castai-kvisor"                       = var.kvisor_values
    "castai-live"                         = var.live_values
  }

  umbrella_chart_values_decoded = merge([
    for comp, vals in local.umbrella_chart_values :
    length(vals) > 0 ? { (comp) = merge([for v in vals : yamldecode(v)]...) } : {}
  ]...)

  umbrella_autoscaler_values = merge(
    local.umbrella_chart_values_decoded,
    # castai-evictor is merged separately because it nests evictor-ext values
    # one level deeper (castai-evictor.castai-evictor-ext).
    length(local.umbrella_evictor_values) > 0 ? { "castai-evictor" = local.umbrella_evictor_values } : {}
  )

  umbrella_values = [yamlencode({ autoscaler = local.umbrella_autoscaler_values })]

  # Shared connection endpoints set once under global.castai.* instead of per-component;
  # all umbrella subcharts consume apiURL/grpcURL from the global scope.
  umbrella_set_global = concat(
    [
      {
        name  = "global.castai.provider"
        value = "aks"
      },
      {
        name  = "global.castai.managedByCASTAI"
        value = !var.self_managed
      },
    ],
    var.api_url != "" ? [
      {
        name  = "global.castai.apiURL"
        value = var.api_url
      },
    ] : [],
    var.grpc_url != "" ? [
      {
        name  = "global.castai.grpcURL"
        value = var.grpc_url
      },
    ] : [],
  )

  umbrella_set = concat(
    [
      {
        name  = "tags.full"
        value = "true"
      }
    ],
    local.umbrella_set_global,
    local.umbrella_set_castai_agent,
    local.umbrella_set_castai_cluster_controller,
    local.umbrella_set_castai_pod_mutator,
    local.umbrella_set_castai_workload_autoscaler,
    local.umbrella_set_castai_workload_autoscaler_exporter,
    local.umbrella_set_castai_evictor,
    local.umbrella_set_castai_pod_pinner,
    local.umbrella_set_castai_spot_handler,
    local.umbrella_set_castai_kvisor,
    local.umbrella_set_castai_live,
  )

  umbrella_set_sensitive = [
    {
      name  = "global.castai.apiKey"
      value = castai_aks_cluster.castai_cluster.cluster_token
    },
  ]
}