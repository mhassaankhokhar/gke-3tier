# Both values go into the GitHub repository as Actions *variables* (not secrets).
# Neither is a credential: the provider name only identifies which trust
# relationship to use, and it is useless without a token from the one repository
# the binding allows.
output "provider_name" {
  description = "Pass to google-github-actions/auth as workload_identity_provider"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "pool_name" {
  description = "Full pool resource name, for adding further principalSet bindings"
  value       = google_iam_workload_identity_pool.github.name
}

output "github_actions_setup" {
  description = "Copy-paste summary of what to configure on the GitHub side after the one-time bootstrap apply"
  value       = <<-EOT
    Set these as repository variables (Settings > Secrets and variables > Actions > Variables):

      GCP_WORKLOAD_IDENTITY_PROVIDER = ${google_iam_workload_identity_pool_provider.github.name}
      GCP_SERVICE_ACCOUNT            = <iam module's ci_service_account_email>

    The workflow then authenticates with no stored key:

      permissions:
        id-token: write        # required — without it GitHub mints no OIDC token
        contents: read

      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: $\{{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: $\{{ vars.GCP_SERVICE_ACCOUNT }}
  EOT
}
