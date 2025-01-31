variable "api_url" {
  type        = string
  description = "URL of alternative CAST AI API to be used during development or testing"
  default     = "https://api.cast.ai"
}

variable "castai_api_token" {
  type        = string
  description = "Optional CAST AI API token created in console.cast.ai API Access keys section. Used only when `wait_for_cluster_ready` is set to true"
  sensitive   = true
  default     = ""
}

variable "grpc_url" {
  type        = string
  description = "gRPC endpoint used by pod-pinner"
  default     = "grpc.cast.ai:443"
}

variable "api_grpc_addr" {
  type        = string
  description = "CAST AI GRPC API address"
  default     = "api-grpc.cast.ai:443"
}

variable "kvisor_controller_extra_args" {
  type        = map(string)
  description = "Extra arguments for the kvisor controller. Optionally enable kvisor to lint Kubernetes YAML manifests, scan workload images and check if workloads pass CIS Kubernetes Benchmarks as well as NSA, WASP and PCI recommendations."
  default = {
    "kube-linter-enabled"        = "true"
    "image-scan-enabled"         = "true"
    "kube-bench-enabled"         = "true"
  }
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the cluster to be connected to CAST AI."
}

variable "aks_cluster_region" {
  type        = string
  description = "Region of the AKS cluster"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "autoscaler_policies_json" {
  type        = string
  description = "Optional json object to override CAST AI cluster autoscaler policies. Deprecated, use `autoscaler_settings` instead."
  default     = null
}

variable "autoscaler_settings" {
  type        = any
  description = "Optional Autoscaler policy definitions to override current autoscaler settings"
  default     = null
}

variable "delete_nodes_on_disconnect" {
  type        = bool
  description = "Optionally delete Cast AI created nodes when the cluster is destroyed"
  default     = false
}

variable "resource_group" {
  type = string
}

variable "additional_resource_groups" {
  type    = list(string)
  default = []
}

variable "node_resource_group" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "http_proxy" {
  type = string
  description = "Address to use for proxying http requests from CAST AI components running directly on nodes."
  default = null
}

variable "https_proxy" {
  type = string
  description = "Address to use for proxying https requests from CAST AI components running directly on nodes."
  default = null
}

variable "no_proxy" {
  type = list(string)
  description = "List of addresses to skip proxying requests from CAST AI components running directly on nodes. Used with http_proxy and https_proxy."
  default = []
}

variable "castai_components_labels" {
  type        = map(any)
  description = "Optional additional Kubernetes labels for CAST AI pods"
  default     = {}
}

variable "castai_components_sets" {
  type        = map(string)
  description = "Optional additional 'set' configurations for helm resources."
  default     = {}
}

variable "node_configurations" {
  type        = any
  description = "Map of AKS node configurations to create"
  default     = {}
}

variable "default_node_configuration" {
  type        = string
  description = "ID of the default node configuration"
  default = ""
}

variable "default_node_configuration_name" {
  type        = string
  description = "Name of the default node configuration"
  default = ""
}

variable "node_templates" {
  type        = any
  description = "Map of node templates to create"
  default     = {}
}

variable "workload_scaling_policies" {
  type        = any
  description = "Map of workload scaling policies to create"
  default     = {}
}

variable "install_security_agent" {
  type        = bool
  default     = false
  description = "Optional flag for installation of security agent (https://docs.cast.ai/product-overview/console/security-insights/)"
}

variable "agent_values" {
  description = "List of YAML formatted string values for agent helm chart"
  type        = list(string)
  default     = []
}

variable "spot_handler_values" {
  description = "List of YAML formatted string values for spot-handler helm chart"
  type        = list(string)
  default     = []
}

variable "cluster_controller_values" {
  description = "List of YAML formatted string values for cluster-controller helm chart"
  type        = list(string)
  default     = []
}

variable "evictor_values" {
  description = "List of YAML formatted string values for evictor helm chart"
  type        = list(string)
  default     = []
}

variable "evictor_ext_values" {
  description = "List of YAML formatted string with evictor-ext values"
  type        = list(string)
  default     = []
}

variable "pod_pinner_values" {
  description = "List of YAML formatted string values for agent helm chart"
  type        = list(string)
  default     = []
}

variable "kvisor_values" {
  description = "List of YAML formatted string values for kvisor helm chart"
  type        = list(string)
  default     = []
}

variable "agent_version" {
  description = "Version of castai-agent helm chart. If not provided, latest version will be used."
  type        = string
  default     = null
}

variable "cluster_controller_version" {
  description = "Version of castai-cluster-controller helm chart. If not provided, latest version will be used."
  type        = string
  default     = null
}

variable "evictor_version" {
  description = "Version of castai-evictor chart. If not provided, latest version will be used."
  type        = string
  default     = null
}

variable "evictor_ext_version" {
  description = "Version of castai-evictor-ext chart. Default latest"
  type        = string
  default     = null
}

variable "pod_pinner_version" {
  description = "Version of pod-pinner helm chart. Default latest"
  type        = string
  default     = null
}

variable "spot_handler_version" {
  description = "Version of castai-spot-handler helm chart. If not provided, latest version will be used."
  type        = string
  default     = null
}

variable "kvisor_version" {
  description = "Version of kvisor chart. If not provided, latest version will be used."
  type        = string
  default     = null
}

variable "self_managed" {
  type        = bool
  default     = false
  description = "Whether CAST AI components' upgrades are managed by a customer; by default upgrades are managed CAST AI central system."
}

variable "wait_for_cluster_ready" {
  type        = bool
  description = "Wait for cluster to be ready before finishing the module execution, this option requires `castai_api_token` to be set"
  default     = false
}

variable "install_workload_autoscaler" {
  type        = bool
  default     = false
  description = "Optional flag for installation of workload autoscaler (https://docs.cast.ai/docs/workload-autoscaling-configuration)"
}

variable "workload_autoscaler_version" {
  description = "Version of castai-workload-autoscaler helm chart. Default latest"
  type        = string
  default     = null
}

variable "workload_autoscaler_values" {
  description = "List of YAML formatted string with cluster-workload-autoscaler values"
  type        = list(string)
  default     = []
}