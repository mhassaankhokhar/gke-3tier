# dev — the only environment.
#
# Apply order matters once, at the start. The identity modules are applied first
# and alone (see docs/bootstrap.md):
#
#   terraform apply -target=module.iam -target=module.workload_identity
#
# because they are what lets the pipeline authenticate; everything below them is
# then created by CI rather than from a workstation.

module "iam" {
  source = "../../modules/iam"

  project_id = var.project_id
  name       = var.name
}

module "workload_identity" {
  source = "../../modules/workload-identity"

  name         = var.name
  github_owner = var.github_owner
  github_repo  = var.github_repo

  # The id, not the email — the binding needs the fully qualified resource.
  ci_service_account_id = module.iam.ci_service_account_id
}

module "network" {
  source = "../../modules/network"

  name   = var.name
  region = var.region
}

module "gke" {
  source = "../../modules/gke"

  project_id = var.project_id
  name       = var.name
  zone       = var.zone

  network_id          = module.network.network_id
  subnet_id           = module.network.subnet_id
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name

  # Scoped account instead of the default compute one, which carries project
  # Editor.
  node_service_account = module.iam.node_service_account_email

  authorized_networks = var.authorized_networks
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  name   = var.name
  region = var.region

  # Registry access is granted here, on the repository, rather than as a project
  # role in the iam module — so neither account can read or write images outside
  # this one repository.
  node_service_account = module.iam.node_service_account_email
  ci_service_account   = module.iam.ci_service_account_email
}

# Binds the CloudNativePG Kubernetes service account to the GCP backup account,
# so the operator writes to GCS without a mounted key.
#
# It sits here rather than in the iam module because it references
# PROJECT.svc.id.goog — the Workload Identity pool that only exists once a
# cluster with workload_identity_config does. Placing it next to module.gke makes
# that ordering a dependency rather than a footnote, and keeps module.iam
# applicable on its own during bootstrap.
resource "google_service_account_iam_member" "postgres_backup" {
  service_account_id = module.iam.backup_service_account_id
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${module.gke.workload_identity_pool}[${var.backup_namespace}/${var.backup_ksa_name}]"
}
