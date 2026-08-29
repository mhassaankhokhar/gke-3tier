variable "namespace" {
  description = "Namespace ArgoCD runs in"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = <<-EOT
    argo-cd chart version — pinned, never a floating range. A GitOps controller
    reconciles on its own schedule, so an unpinned chart can install something
    unreviewed with no commit behind it. Bump this file to upgrade; that bump is
    the review.
  EOT
  type        = string
  default     = "10.4.1"
}

variable "apps_chart_version" {
  description = "argocd-apps chart version — pinned for the same reason as the ArgoCD chart itself"
  type        = string
  default     = "2.0.5"
}

variable "repo_url" {
  description = <<-EOT
    Git repository ArgoCD reconciles from — the separate GitOps repo, not this
    one. SSH URL because it is private: ArgoCD authenticates with a read-only
    deploy key that External Secrets projects from Secret Manager.
  EOT
  type        = string
}

variable "target_revision" {
  description = "Branch or tag the root Application tracks"
  type        = string
  default     = "main"
}

variable "apps_path" {
  description = "Directory of Application manifests, relative to the repo root. Everything in it is reconciled recursively."
  type        = string
  default     = "argocd/apps"
}
