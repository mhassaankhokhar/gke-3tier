# Set as GitHub repository variables. Not credentials: unusable without an
# OIDC token from the permitted repository.
output "gcp_workload_identity_provider" {
  description = "GitHub Actions variable: GCP_WORKLOAD_IDENTITY_PROVIDER"
  value       = module.workload_identity.provider_name
}

output "gcp_service_account" {
  description = "GitHub Actions variable: GCP_SERVICE_ACCOUNT"
  value       = module.iam.ci_service_account_email
}

# Read by envs/dev through terraform_remote_state.
output "node_service_account_email" {
  value = module.iam.node_service_account_email
}

output "ci_service_account_email" {
  value = module.iam.ci_service_account_email
}

output "backup_service_account_email" {
  value = module.iam.backup_service_account_email
}

output "backup_service_account_id" {
  value = module.iam.backup_service_account_id
}

output "external_secrets_service_account_email" {
  value = module.iam.external_secrets_service_account_email
}

output "external_secrets_service_account_id" {
  value = module.iam.external_secrets_service_account_id
}
