output "repository_id" {
  description = "Full Artifact Registry resource id"
  value       = google_artifact_registry_repository.main.id
}

output "repository_name" {
  description = "Repository (folder) name"
  value       = google_artifact_registry_repository.main.name
}

# The prefix every image path is built from. CI appends "/api:tag" or
# "/web:tag" — deriving it here keeps the region and project out of the
# workflow files, which is what lets the repo stay publishable.
output "repository_url" {
  description = "Image path prefix, e.g. asia-south1-docker.pkg.dev/PROJECT/gke-3tier"
  value       = "${google_artifact_registry_repository.main.location}-docker.pkg.dev/${google_artifact_registry_repository.main.project}/${google_artifact_registry_repository.main.name}"
}
