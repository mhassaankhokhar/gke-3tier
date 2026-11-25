output "cluster_name" {
  description = "Cluster name, for `gcloud container clusters get-credentials`"
  value       = google_container_cluster.main.name
}

output "cluster_endpoint" {
  description = "Control plane endpoint"
  value       = google_container_cluster.main.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA, for a kubernetes/helm provider that talks to this cluster directly"
  value       = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool — the KSA→GSA bindings reference this"
  value       = "${var.project_id}.svc.id.goog"
}

# Workloads pin themselves with nodeSelector on these labels; pools are untainted.
output "node_labels" {
  description = "workload label values: pin Postgres and Longhorn to stateful, prefer stateless for web/api"
  value = {
    stateful  = "stateful"
    stateless = "stateless"
  }
}
