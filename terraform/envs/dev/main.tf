# dev environment, applied by CI. Own directory and state per environment
# (not CLI workspaces). Identity is read from bootstrap's state, so a destroy
# here leaves the pipeline able to rebuild.

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = var.bootstrap_state_prefix
  }
}

locals {
  node_sa   = data.terraform_remote_state.bootstrap.outputs.node_service_account_email
  ci_sa     = data.terraform_remote_state.bootstrap.outputs.ci_service_account_email
  backup_sa = data.terraform_remote_state.bootstrap.outputs.backup_service_account_id
  eso_sa    = data.terraform_remote_state.bootstrap.outputs.external_secrets_service_account_id
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

  # Scoped node account from bootstrap, not the default compute account.
  node_service_account = local.node_sa

  authorized_networks = var.authorized_networks

  # Measurement done; result is in spot_machine_type's description.
  probe_pool_enabled = false
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  name   = var.name
  region = var.region

  # Registry access is granted on the repository, not the project.
  node_service_account = local.node_sa
  ci_service_account   = local.ci_sa
}

# CloudNativePG KSA → GCP backup account. Here, not in bootstrap: it needs the
# cluster's Workload Identity pool.
resource "google_service_account_iam_member" "postgres_backup" {
  service_account_id = local.backup_sa
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${module.gke.workload_identity_pool}[${var.backup_namespace}/${var.backup_ksa_name}]"
}

# ESO KSA → its GCP account, for reading the Cloudflare token. Here for the same reason.
resource "google_service_account_iam_member" "external_secrets" {
  service_account_id = local.eso_sa
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${module.gke.workload_identity_pool}[${var.eso_namespace}/${var.eso_ksa_name}]"
}

# ESO, the ClusterSecretStore and ArgoCD's deploy key: needed to read Git, so not from Git.
module "cluster_seed" {
  source = "../../modules/cluster-seed"

  project_id                = var.project_id
  cluster_name              = module.gke.cluster_name
  cluster_location          = var.zone
  repo_url                  = var.repo_url
  gcp_service_account_email = data.terraform_remote_state.bootstrap.outputs.external_secrets_service_account_email

  depends_on = [
    module.gke,
    # The binding must exist before ESO's first secret sync.
    google_service_account_iam_member.external_secrets,
  ]
}

# ArgoCD, after the seed so the repo credential exists. Everything else in the
# cluster comes from the gke-3tier-gitops repository.
module "argocd" {
  source = "../../modules/argocd"

  repo_url        = var.repo_url
  target_revision = var.target_revision

  depends_on = [module.cluster_seed]
}
