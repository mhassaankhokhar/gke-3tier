# dev environment — applied by CI, never by hand.
#
# One directory per environment, each with its own state and its own backend
# config. Not Terraform CLI workspaces: those keep every environment's state in
# one backend behind one set of credentials, so an apply in the wrong workspace
# reaches production. HashiCorp's own guidance points them at temporary parallel
# copies (a per-PR stack), not at environment separation.
#
# Identity lives in bootstrap/ with its own state. This configuration READS those
# accounts and never creates them, so `terraform destroy` here removes the
# cluster, network and registry and leaves the pipeline able to rebuild them.

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

  # Scoped account from bootstrap, instead of the default compute one which
  # carries project Editor.
  node_service_account = local.node_sa

  authorized_networks = var.authorized_networks
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  name   = var.name
  region = var.region

  # Registry access is granted on the repository rather than as a project role,
  # so neither account can reach images outside this one repository.
  node_service_account = local.node_sa
  ci_service_account   = local.ci_sa
}

# Binds the CloudNativePG Kubernetes service account to the GCP backup account.
#
# Here, not in bootstrap, because it references PROJECT.svc.id.goog — the
# Workload Identity pool that exists only once a cluster with
# workload_identity_config does. Next to module.gke, the ordering comes from the
# dependency graph rather than from a rule someone has to remember.
resource "google_service_account_iam_member" "postgres_backup" {
  service_account_id = local.backup_sa
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${module.gke.workload_identity_pool}[${var.backup_namespace}/${var.backup_ksa_name}]"
}
