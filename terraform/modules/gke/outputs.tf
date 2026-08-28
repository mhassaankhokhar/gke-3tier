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

# Surfaced so the Kubernetes manifests do not have to hardcode the toleration
# key/value that the stateful pool's taint uses.
output "stateful_taint" {
  description = "Taint applied to the stateful pool; Postgres and Longhorn must tolerate it"
  value = {
    key    = "workload"
    value  = "stateful"
    effect = "NoSchedule"
  }
}
