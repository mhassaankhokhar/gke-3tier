variable "project_id" {
  description = "GCP project id"
  type        = string
}

variable "name" {
  description = <<-EOT
    Prefix for account ids. GCP account_id is limited to 30 characters and must be
    lowercase alphanumeric with hyphens, so keep this short — "gke-3tier" leaves
    room for the "-backup" suffix.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,20}$", var.name))
    error_message = "name must be lowercase alphanumeric/hyphen, start with a letter, and stay short enough that name + '-backup' fits GCP's 30-character account_id limit."
  }
}

variable "backup_namespace" {
  description = "Kubernetes namespace the CloudNativePG cluster runs in — half of the Workload Identity binding"
  type        = string
  default     = "database"
}

variable "backup_ksa_name" {
  description = <<-EOT
    Kubernetes service account bound to the GCP backup account. This must match
    the KSA the CloudNativePG cluster actually uses; a mismatch fails at backup
    time with a permission error, not at apply time.
  EOT
  type        = string
  default     = "postgres-backup"
}
