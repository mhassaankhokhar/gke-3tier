# ── Bootstrap outputs ────────────────────────────────────────────────────────
# These two are what the one-time local apply exists to produce. Set them as
# GitHub repository *variables* — neither is a credential: the provider name only
# identifies a trust relationship, and it is unusable without an OIDC token from
# the single repository the binding permits.

output "gcp_workload_identity_provider" {
  description = "GitHub Actions variable: GCP_WORKLOAD_IDENTITY_PROVIDER"
  value       = module.workload_identity.provider_name
}

output "gcp_service_account" {
  description = "GitHub Actions variable: GCP_SERVICE_ACCOUNT"
  value       = module.iam.ci_service_account_email
}

# ── Cluster ──────────────────────────────────────────────────────────────────
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

# ── Service accounts ─────────────────────────────────────────────────────────
output "node_service_account" {
  description = "Scoped node account, replacing the default compute one"
  value       = module.iam.node_service_account_email
}

output "backup_service_account" {
  description = "Bound to the CloudNativePG Kubernetes service account for GCS backups"
  value       = module.iam.backup_service_account_email
}
