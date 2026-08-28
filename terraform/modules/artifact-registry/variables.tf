variable "name" {
  description = "Repository id — becomes the folder in the image path"
  type        = string
}

variable "region" {
  description = "Region for the repository. Keep it the same as the cluster: a cross-region pull is slower and bills as egress."
  type        = string
}

variable "untagged_retention" {
  description = <<-EOT
    How long untagged images survive. These are the layers left behind when a tag
    is moved to a newer build — nothing references them, but they still bill.
    Terraform wants a duration string in seconds; 7d = 604800s.
  EOT
  type        = string
  default     = "604800s"
}

variable "keep_recent_count" {
  description = "How many recent versions to protect from the delete rule, so a rollback target always exists."
  type        = number
  default     = 10
}

variable "cleanup_dry_run" {
  description = <<-EOT
    true = policies report what they would delete without deleting it. Start
    here, check Cloud Logging, then set false. A cleanup policy that deletes the
    image currently running in production is not recoverable.
  EOT
  type        = bool
  default     = true
}

variable "node_service_account" {
  description = "GKE node service account, granted reader so pulls need no imagePullSecret. null skips the grant."
  type        = string
  default     = null
}

variable "ci_service_account" {
  description = "Service account the GitHub Actions pipeline impersonates via Workload Identity Federation, granted writer. null skips the grant."
  type        = string
  default     = null
}
