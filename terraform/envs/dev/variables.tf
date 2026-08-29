variable "project_id" {
  description = "GCP project id. Lives in terraform.tfvars, which is gitignored."
  type        = string
}

variable "region" {
  description = "Region for the network and registry. Same region as the state bucket and cluster — splitting them costs egress and latency for nothing."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = <<-EOT
    Zone for the cluster. Zonal rather than regional: a regional control plane
    replicates across zones and multiplies node count — right for production,
    roughly triple the burn for a project meant to outlive a trial credit. A zone
    outage takes the cluster down; accepted, and recorded in docs/.
  EOT
  type        = string
  default     = "us-central1-a"
}

variable "name" {
  description = "Prefix applied to every resource"
  type        = string
  default     = "gke-3tier"
}

# ── Reading bootstrap's state ────────────────────────────────────────────────
variable "state_bucket" {
  description = "Bucket holding both states. Passed in rather than committed, same as the backend config."
  type        = string
}

variable "bootstrap_state_prefix" {
  description = "Prefix of the bootstrap state within that bucket — the identity outputs are read from here, never written"
  type        = string
  default     = "gke-3tier/bootstrap"
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

# ── CloudNativePG identity ───────────────────────────────────────────────────
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

# ── GitOps ───────────────────────────────────────────────────────────────────
variable "repo_url" {
  description = "Repository ArgoCD reconciles from. Public, so no repo credentials are needed in the cluster."
  type        = string
  default     = "https://github.com/mhassaankhokhar/gke-3tier.git"
}

variable "target_revision" {
  description = "Branch the root Application tracks"
  type        = string
  default     = "main"
}

# ── External Secrets identity ────────────────────────────────────────────────
variable "eso_namespace" {
  description = "Namespace External Secrets Operator runs in — half of the Workload Identity binding"
  type        = string
  default     = "external-secrets"
}

variable "eso_ksa_name" {
  description = "ESO's Kubernetes service account. Must match the Helm values exactly; a mismatch fails when a secret is first synced, not at apply time."
  type        = string
  default     = "external-secrets"
}
