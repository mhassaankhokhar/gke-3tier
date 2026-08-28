output "node_service_account_email" {
  description = "Scoped account for GKE node pools — pass to the gke module so nodes do not fall back to the default compute account"
  value       = google_service_account.nodes.email
}

output "ci_service_account_email" {
  description = "Account GitHub Actions impersonates; the workload-identity module federates to it"
  value       = google_service_account.ci.email
}

output "ci_service_account_id" {
  description = "Fully qualified CI account id, needed for the Workload Identity Federation binding"
  value       = google_service_account.ci.name
}

output "backup_service_account_email" {
  description = "Account CloudNativePG uses for GCS backups; the storage module grants it object access on the bucket"
  value       = google_service_account.backup.email
}
