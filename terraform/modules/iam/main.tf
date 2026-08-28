# User-managed service accounts for the cluster and the pipeline.
#
# Worth being explicit about what is and is not creatable here, because it is
# the opposite of AWS:
#
#   Creatable (what this module makes) — user-managed service accounts. In GCP a
#   service account is a first-class identity you own. AWS has no equivalent
#   object; there, EC2/ECS attach *roles* via instance profiles and task roles.
#
#   NOT creatable — Google-owned accounts, the real counterpart of AWS's
#   service-linked roles:
#     * default accounts, e.g. PROJECT_NUMBER-compute@developer.gserviceaccount.com,
#       created automatically when the Compute API is enabled
#     * service agents, e.g. service-PROJECT_NUMBER@container-engine-robot.iam
#       .gserviceaccount.com, created and managed by Google
#   You can grant those roles; you cannot create, delete or re-scope them.
#
# The default compute account carries project-level Editor. That is why the node
# pools take a scoped account from here instead of falling back to it.

# ── Node service account ─────────────────────────────────────────────────────
resource "google_service_account" "nodes" {
  account_id   = "${var.name}-nodes"
  display_name = "${var.name} GKE nodes"
  description  = "Scoped replacement for the default compute service account, which holds project Editor"
}

# The minimum a GKE node needs to register, ship logs and export metrics. Image
# pull permission is NOT here — that is granted on the Artifact Registry
# repository itself, so it stays scoped to one repository rather than the project.
locals {
  node_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ]
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# ── CI service account ───────────────────────────────────────────────────────
# Impersonated by GitHub Actions through Workload Identity Federation. No key is
# ever created for it — that is the point, and why keys are gitignored.
resource "google_service_account" "ci" {
  account_id   = "${var.name}-ci"
  display_name = "${var.name} CI pipeline"
  description  = "Impersonated by GitHub Actions via Workload Identity Federation; has no keys"

  # Second line of defence behind state separation: even a destroy run in the
  # wrong directory is refused at plan time. This account is what lets CI
  # authenticate at all — losing it means redoing the whole bootstrap.
  lifecycle {
    prevent_destroy = true
  }
}

# container.developer manages workloads inside the cluster but cannot create,
# delete or resize clusters — the pipeline deploys, it does not own the
# infrastructure. Registry write is granted on the repository, not here.
resource "google_project_iam_member" "ci" {
  for_each = toset(["roles/container.developer"])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci.email}"
}

# ── Database backup service account ──────────────────────────────────────────
# CloudNativePG writes base backups and WAL to GCS. The Kubernetes service
# account is bound to this one through Workload Identity, so the operator
# authenticates without a mounted key file.
resource "google_service_account" "backup" {
  account_id   = "${var.name}-backup"
  display_name = "${var.name} database backups"
  description  = "Bound to the CloudNativePG Kubernetes service account via Workload Identity"
}

# NOTE: the Kubernetes-service-account binding for this account is deliberately
# NOT here. It references the cluster's Workload Identity pool
# (PROJECT.svc.id.goog), which does not exist until a GKE cluster with
# workload_identity_config has been created — and this module is applied during
# bootstrap, before any cluster. The binding lives in the env alongside the gke
# module so ordering falls out of the dependency graph instead of being a rule
# someone has to remember.
