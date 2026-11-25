# One Docker repository for all images; each image is a path within it
# (<region>-docker.pkg.dev/<project>/<repo>/api), so IAM and cleanup are set once.

resource "google_artifact_registry_repository" "main" {
  location      = var.region
  repository_id = var.name
  description   = "Container images for ${var.name}"
  format        = "DOCKER"

  docker_config {
    # Mutable so a failed release can be re-pushed under the same tag.
    immutable_tags = false
  }

  # ── Cleanup ───────────────────────────────────────────────────────────────
  # Storage is billed per GB. Keep-rules win over delete-rules, so recent
  # versions survive the age-based delete.

  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = var.untagged_retention
    }
  }

  cleanup_policies {
    id     = "keep-recent-releases"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.keep_recent_count
    }
  }

  # true = report only (Cloud Logging). Set false once the reported deletions look right.
  cleanup_policy_dry_run = var.cleanup_dry_run
}

# Nodes pull with their own service account: no imagePullSecret.
resource "google_artifact_registry_repository_iam_member" "node_reader" {
  count = var.node_service_account == null ? 0 : 1

  location   = google_artifact_registry_repository.main.location
  repository = google_artifact_registry_repository.main.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.node_service_account}"
}

# Granted to the federated CI account; no key.
resource "google_artifact_registry_repository_iam_member" "ci_writer" {
  count = var.ci_service_account == null ? 0 : 1

  location   = google_artifact_registry_repository.main.location
  repository = google_artifact_registry_repository.main.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.ci_service_account}"
}
