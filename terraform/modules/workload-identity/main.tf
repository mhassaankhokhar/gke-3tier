# GitHub Actions → GCP via Workload Identity Federation: a short-lived OIDC
# token per run, no stored key. Applied from bootstrap/, never by CI.

locals {
  # Deleted pools keep their id reserved for 30 days; a suffix allows a rebuild inside that window.
  pool_id = var.pool_suffix == "" ? "${var.name}-github" : "${var.name}-github-${var.pool_suffix}"
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = local.pool_id
  display_name              = "${var.name} GitHub"
  description               = "Federates GitHub Actions OIDC tokens to GCP service accounts"

  # A destroyed pool can't be recreated with the same id for 30 days.
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

  # attribute.repository is what the binding filters on; the rest allow narrower policies later.
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # Required: without it the provider trusts every GitHub Actions token.
  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"
}

# Narrower than the provider condition: one repository, not the whole owner.
resource "google_service_account_iam_member" "ci" {
  service_account_id = var.ci_service_account_id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_repo}"
}
