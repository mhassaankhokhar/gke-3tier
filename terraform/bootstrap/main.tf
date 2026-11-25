# Bootstrap: CI's identity, in its own state and applied by hand, so a
# destroy in envs/ can't reach it. See docs/bootstrap.md.

module "iam" {
  source = "../modules/iam"

  project_id   = var.project_id
  name         = var.name
  state_bucket = var.state_bucket

  # Per-secret grants: a new secret needs adding here.
  readable_secrets = var.readable_secrets
}

module "workload_identity" {
  source = "../modules/workload-identity"

  name         = var.name
  github_owner = var.github_owner
  github_repo  = var.github_repo

  # The fully qualified id, not the email.
  ci_service_account_id = module.iam.ci_service_account_id

  # Set because the original gke-3tier-github pool id was soft-deleted. That
  # hold has lapsed; return to "" only if the id matters.
  pool_suffix = var.pool_suffix
}
