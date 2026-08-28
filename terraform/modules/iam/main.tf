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

# What CI needs to apply the infrastructure — and deliberately no more.
#
# Withheld: iam.serviceAccountAdmin and resourcemanager.projectIamAdmin. Without
# them the pipeline can build the whole stack but cannot create service accounts
# or grant itself project roles, so a compromised workflow cannot widen its own
# access. The cost is that IAM changes stay a bootstrap task.
#
# viewer is here because `plan` refreshes every resource in state, including the
# accounts this module creates, and reading those needs project-wide read.
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

# Terraform state lives in a bucket created out-of-band (the backend has to exist
# before the configuration that uses it), so this grants access to it rather than
# creating it. Without this, CI's very first `terraform init` fails on
# storage.objects.list.
data "google_storage_bucket" "state" {
  name = var.state_bucket
}

resource "google_storage_bucket_iam_member" "ci_state" {
  bucket = data.google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ci.email}"
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

# CI manages the KSA→GSA binding on this one account, so it needs setIamPolicy
# on it. Granted at the RESOURCE level, not project-wide: CI can change this
# account's policy and no other, and still cannot create or delete accounts.
resource "google_service_account_iam_member" "ci_manages_backup" {
  service_account_id = google_service_account.backup.name
  role               = "roles/iam.serviceAccountAdmin"
  member             = "serviceAccount:${google_service_account.ci.email}"
}

# NOTE: the Kubernetes-service-account binding for this account is deliberately
# NOT here. It references the cluster's Workload Identity pool
# (PROJECT.svc.id.goog), which does not exist until a GKE cluster with
# workload_identity_config has been created — and this module is applied during
# bootstrap, before any cluster. The binding lives in the env alongside the gke
# module so ordering falls out of the dependency graph instead of being a rule
# someone has to remember.
