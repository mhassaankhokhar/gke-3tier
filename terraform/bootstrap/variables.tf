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

  # Granted per secret, not project-wide. A secret not listed here gets
  # PermissionDenied on secretmanager.versions.access.
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
