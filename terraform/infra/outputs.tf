output "cluster_name" {
  description = "For: gcloud container clusters get-credentials <name> --zone <zone>"
  value       = module.gke.cluster_name
}

output "cluster_zone" {
  value = var.zone
}

output "registry_url" {
  description = "Image path prefix; CI appends /api:tag and /web:tag"
  value       = module.artifact_registry.repository_url
}

output "network_name" {
  value = module.network.network_name
}
