# Bootstrap — identity only, applied once by a human.
#
# This configuration exists so that `terraform destroy` in infra/ CANNOT remove
# the credentials the pipeline runs on. That is a property of the state file, not
# of anyone's discipline: these resources are simply not in infra's state, so no
# command run there can reach them.
#
# The earlier layout kept everything in one state and used
# `-target=module.iam ...` to apply "just the bootstrap". That protects one
# command and nothing after it — a later plain `terraform destroy` took the
# service accounts and the Workload Identity pool along with the cluster, and the
# pool then stayed soft-deleted for 30 days with its id reserved.
#
# Apply this by hand, then leave it alone. See docs/bootstrap.md.

module "iam" {
  source = "../modules/iam"

  project_id   = var.project_id
  name         = var.name
  state_bucket = var.state_bucket

  # Read access is granted per secret, so a new secret is a deliberate addition
  # here rather than something the operator silently picks up.
  readable_secrets = var.readable_secrets
}

module "workload_identity" {
  source = "../modules/workload-identity"

  name         = var.name
  github_owner = var.github_owner
  github_repo  = var.github_repo

  # The fully qualified id, not the email.
  ci_service_account_id = module.iam.ci_service_account_id

  # Non-empty because the original gke-3tier-github pool is soft-deleted until
  # late September 2026. Drop it back to "" once that lapses, if the id matters.
  pool_suffix = var.pool_suffix
}
