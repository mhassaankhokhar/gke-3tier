# User-managed service accounts for the nodes and the pipeline. The default
# compute account has project Editor, so nodes use a scoped account from here.

# ── Node service account ─────────────────────────────────────────────────────
resource "google_service_account" "nodes" {
  account_id   = "${var.name}-nodes"
  display_name = "${var.name} GKE nodes"
  description  = "Scoped replacement for the default compute service account, which holds project Editor"
}

# Minimum a GKE node needs. Image pull is granted on the Artifact Registry
# repository instead, to keep it scoped to one repository.
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
# Impersonated by GitHub Actions through Workload Identity Federation; no key.
resource "google_service_account" "ci" {
  account_id   = "${var.name}-ci"
  display_name = "${var.name} CI pipeline"
  description  = "Impersonated by GitHub Actions via Workload Identity Federation; has no keys"

  # CI cannot authenticate without this account.
  lifecycle {
    prevent_destroy = true
  }
}

# What CI needs to apply the stack. iam.serviceAccountAdmin and
# resourcemanager.projectIamAdmin are withheld so CI cannot widen its own access.
# viewer: plan refreshes the accounts in state.
locals {
  ci_roles = [
    "roles/viewer",
    "roles/compute.networkAdmin",   # VPC, subnets, router, NAT
    "roles/container.admin",        # cluster and node pools
    "roles/artifactregistry.admin", # the image repository and its IAM
    "roles/iam.serviceAccountUser", # attach the node account to the cluster
  ]
}

resource "google_project_iam_member" "ci" {
  for_each = toset(local.ci_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci.email}"
}

# The state bucket exists before Terraform (backend), so access is granted, not the bucket created.
data "google_storage_bucket" "state" {
  name = var.state_bucket
}

resource "google_storage_bucket_iam_member" "ci_state" {
  bucket = data.google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ci.email}"
}

# ── Database backup service account ──────────────────────────────────────────
# CloudNativePG writes backups and WAL to GCS via Workload Identity.
resource "google_service_account" "backup" {
  account_id   = "${var.name}-backup"
  display_name = "${var.name} database backups"
  description  = "Bound to the CloudNativePG Kubernetes service account via Workload Identity"
}

# Resource-level setIamPolicy so CI can manage the KSA→GSA bindings of these
# accounts only. One entry per account: adding another is a deliberate change.

# The KSA→GSA binding lives in envs/dev: it needs the cluster's Workload
# Identity pool, which doesn't exist at bootstrap.

# ── External Secrets service account ─────────────────────────────────────────
# Reads the Cloudflare token from Secret Manager via Workload Identity.
resource "google_service_account" "external_secrets" {
  account_id   = "${var.name}-eso"
  display_name = "${var.name} External Secrets"
  description  = "Reads secrets from Secret Manager on behalf of External Secrets Operator"
}

# accessor: reads secret values only.
resource "google_secret_manager_secret_iam_member" "external_secrets" {
  for_each = toset(var.readable_secrets)

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.external_secrets.email}"
}

# KSA→GSA binding is in envs/dev, as for the backup account.

resource "google_service_account_iam_member" "ci_manages_bindings" {
  for_each = {
    backup          = google_service_account.backup.name
    external_secret = google_service_account.external_secrets.name
  }

  service_account_id = each.value
  role               = "roles/iam.serviceAccountAdmin"
  member             = "serviceAccount:${google_service_account.ci.email}"
}
