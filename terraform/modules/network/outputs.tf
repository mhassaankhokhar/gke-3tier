output "network_id" {
  description = "VPC id, for the cluster and any firewall rules"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "VPC name"
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "Node subnet id"
  value       = google_compute_subnetwork.nodes.id
}

output "subnet_name" {
  description = "Node subnet name"
  value       = google_compute_subnetwork.nodes.name
}

# The GKE module references these by name rather than hardcoding the strings in
# two places — a mismatch here fails at cluster-create time with an unhelpful
# "secondary range not found".
output "pods_range_name" {
  description = "Secondary range name for pods"
  value       = google_compute_subnetwork.nodes.secondary_ip_range[0].range_name
}

output "services_range_name" {
  description = "Secondary range name for services"
  value       = google_compute_subnetwork.nodes.secondary_ip_range[1].range_name
}
