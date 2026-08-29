output "secret_store_name" {
  description = "ClusterSecretStore other ExternalSecrets reference — including the ones that arrive later from Git"
  value       = var.secret_store_name
}

output "eso_namespace" {
  value = helm_release.external_secrets.namespace
}
