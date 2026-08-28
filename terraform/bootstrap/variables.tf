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
