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

output "argocd_password_command" {
  description = "Read the generated ArgoCD admin password (not an output — that would put it in state)"
  value       = module.argocd.initial_password_command
}

output "argocd_port_forward" {
  description = "Reach the ArgoCD UI before an ingress exists"
  value       = module.argocd.port_forward_command
}
