variable "project_id" {
  description = "GCP project id. Lives in terraform.tfvars, which is gitignored."
  type        = string
}

variable "region" {
  description = "Region for the network, registry and state bucket. Keep all three together — split across regions costs egress and latency for nothing."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = <<-EOT
    Zone for the cluster. Zonal rather than regional: a regional control plane
    replicates across zones and multiplies node count, which is right for
    production and roughly triples the burn rate for a project meant to outlive a
    trial credit. Must sit inside var.region.
  EOT
  type        = string
  default     = "us-central1-a"
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

variable "authorized_networks" {
  description = "CIDRs allowed to reach the control-plane endpoint. Narrow to your own IP when it is stable."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{
    cidr_block   = "0.0.0.0/0"
    display_name = "all (narrow this)"
  }]
}

variable "backup_namespace" {
  description = "Namespace the CloudNativePG cluster runs in — half of the Workload Identity binding"
  type        = string
  default     = "database"
}

variable "backup_ksa_name" {
  description = "Kubernetes service account the CloudNativePG cluster uses. Must match the manifests exactly; a mismatch fails at backup time, not at apply time."
  type        = string
  default     = "postgres-backup"
}
