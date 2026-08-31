variable "project_id" {
  description = "GCP project id. Lives in terraform.tfvars, which is gitignored."
  type        = string
}

variable "region" {
  description = "Region — kept here only so bootstrap and infra read the same tfvars shape"
  type        = string
  default     = "us-central1"
}

variable "name" {
  description = "Prefix applied to every resource"
  type        = string
  default     = "gke-3tier"
}

variable "github_owner" {
  description = "GitHub account that owns the repository — the OIDC provider's attribute_condition pins to this"
  type        = string
}

variable "github_repo" {
  description = "Repository name without the owner. Only this repo can impersonate the CI account."
  type        = string
}

variable "pool_suffix" {
  description = "Suffix for the Workload Identity pool id — set when a same-named pool is still soft-deleted"
  type        = string
  default     = ""
}

variable "state_bucket" {
  description = "Terraform state bucket, created out-of-band. Bootstrap grants CI access to it."
  type        = string
}

variable "readable_secrets" {
  description = "Secret Manager secrets External Secrets Operator may read"
  type        = list(string)

  # Granted per secret, not project-wide: the accessor role on the whole project
  # would let one compromised operator read every secret the project ever holds.
  # The cost is that a new secret is inert until it is named here — the symptom
  # is PermissionDenied on secretmanager.versions.access, from a binding that
  # looks correct because it is correct, just not for this secret.
  #
  # This list lives in bootstrap, which is applied by hand. Adding a secret is
  # therefore a deliberate step, which is the intent.
  default = [
    "cloudflare-api-token",
    "argocd-gitops-ssh-key",
    "tailscale-oauth-client-id",
    "tailscale-oauth-client-secret",
    "postgres-app-password",
    "web-session-secret",
    "grafana-admin-password",
  ]
}
