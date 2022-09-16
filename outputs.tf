output "cluster_id" {
  value       = castai_aks_cluster.castai_cluster.id
  description = "CAST.AI cluster id, which can be used for accessing cluster data using API"
  sensitive   = true
}

output "castai_node_configurations" {
  description = "Map of node configurations ids by name"
  value       = {
    for k, v in castai_node_configuration.this : v.name => v.id
  }
}