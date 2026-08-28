# One Docker repository holding every image in the project.
#
# Artifact Registry treats a repository as a folder, so api, web and anything
# added later live as paths inside it:
#
#   <region>-docker.pkg.dev/<project>/<repo>/api:v1.0.0
#   <region>-docker.pkg.dev/<project>/<repo>/web:v1.0.0
#
# ECR has no such nesting — there, each image needs its own repository. Keeping
# one repository here means IAM, cleanup policies and scanning are configured
# once instead of once per service.

resource "google_artifact_registry_repository" "main" {
  location      = var.region
  repository_id = var.name
  description   = "Container images for ${var.name}"
  format        = "DOCKER"

  docker_config {
    # Tags stay mutable: the deploy pipeline is tag-driven (v1.2.3) and a
    # re-run of a failed release would be blocked by immutable tags. Immutable
    # is the safer production setting; this project favours being able to retry.
    immutable_tags = false
  }

  # ── Cleanup ───────────────────────────────────────────────────────────────
  # CI pushes an image on every release tag, and storage is billed per GB. Left
  # alone this grows forever, which is a quiet way to burn a trial credit.
  #
  # Order matters: keep-rules win over delete-rules in Artifact Registry, so the
  # "keep recent versions" rule below protects releases from the age-based
  # delete rule above it.

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

  # Dry run first: with this true the policies only report what they would have
  # deleted (visible in Cloud Logging) instead of deleting it. Flip to false
  # once the reported deletions look right.
  cleanup_policy_dry_run = var.cleanup_dry_run
}

# Nodes pull images with their own service account, so no imagePullSecret and no
# credential-refresh job is needed in the cluster — the thing that makes ECR on
# Kubernetes awkward.
resource "google_artifact_registry_repository_iam_member" "node_reader" {
  count = var.node_service_account == null ? 0 : 1

  location   = google_artifact_registry_repository.main.location
  repository = google_artifact_registry_repository.main.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.node_service_account}"
}

# The CI pipeline pushes; it authenticates through Workload Identity Federation,
# so this grant is to the federated service account, not to a stored key.
resource "google_artifact_registry_repository_iam_member" "ci_writer" {
  count = var.ci_service_account == null ? 0 : 1

  location   = google_artifact_registry_repository.main.location
  repository = google_artifact_registry_repository.main.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.ci_service_account}"
}
