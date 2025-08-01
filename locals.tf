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


  # Common conditional SENSITIVE values that we pass to helm_releases.
  # Set up as lists so they can be concatenated.
  set_sensitive_apikey = [{
    name  = "castai.apiKey"
    value = castai_aks_cluster.castai_cluster.cluster_token
  }]
}