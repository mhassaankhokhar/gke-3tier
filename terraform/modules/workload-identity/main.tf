# GitHub Actions -> GCP via Workload Identity Federation.
#
# GitHub mints a short-lived OIDC token for each workflow run; GCP trades it for
# a token on the CI service account. Nothing long-lived is stored — no service
# account key exists to leak, which is why this repo can be public.
#
# BOOTSTRAP: this module is the one piece that cannot be applied by the pipeline,
# because it is what gives the pipeline its credentials. Apply it once from a
# workstation with user ADC (`gcloud auth application-default login`), put the
# outputs into the repo's Actions variables, and every later apply runs in CI.

locals {
  # Suffix exists only to sidestep a soft-deleted predecessor. Deleting a pool
  # reserves its id for 30 days, so rebuilding from scratch inside that window
  # needs either `undelete` or a new id — this makes the second option a one-line
  # change instead of renaming the whole project.
  pool_id = var.pool_suffix == "" ? "${var.name}-github" : "${var.name}-github-${var.pool_suffix}"
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = local.pool_id
  display_name              = "${var.name} GitHub"
  description               = "Federates GitHub Actions OIDC tokens to GCP service accounts"

  # Deleting this pool soft-deletes it for 30 days with the id reserved, so a
  # rebuild inside that window fails with "already exists" and needs an
  # `undelete`. Refuse the destroy rather than discover that later.
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = local.pool_id
  display_name                       = "GitHub Actions"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # Claims carried over from the GitHub token. attribute.repository is the one
  # the binding below filters on; the others exist so policies can get narrower
  # later (a specific branch, a specific environment) without re-federating.
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # THE load-bearing line. Without a condition scoped to this owner, the provider
  # trusts every GitHub Actions token on the internet: any repository anywhere
  # could present one and impersonate the CI account. GCP now refuses to create a
  # GitHub provider with no condition for exactly this reason.
  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"
}

# Narrower still than the provider condition: the provider trusts the owner, this
# binding trusts one repository under that owner. Two layers, so a second repo in
# the same account cannot deploy this project by accident.
resource "google_service_account_iam_member" "ci" {
  service_account_id = var.ci_service_account_id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repo}"
}
