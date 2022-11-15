variable "api_url" {
  type        = string
  description = "URL of alternative CAST AI API to be used during development or testing"
  default     = "https://api.cast.ai"
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
  description = "Optional json object to override CAST AI cluster autoscaler policies"
  default     = ""
}

variable "delete_nodes_on_disconnect" {
  type        = bool
  description = "Optionally delete Cast AI created nodes when the cluster is destroyed"
  default     = false
}

variable "resource_group" {
  type = string
}

variable "node_resource_group" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "castai_components_labels" {
  type        = map
  description = "Optional additional Kubernetes labels for CAST AI pods"
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
}

// https://docs.cast.ai/product-overview/console/security-insights/
variable "install_security_agent" {
  type = bool
  default = false
  description = "Optional flag for installation of security agent (https://docs.cast.ai/product-overview/console/security-insights/)"
}
