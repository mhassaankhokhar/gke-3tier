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
