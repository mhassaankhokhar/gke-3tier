variable "project_id" {
  description = "GCP project holding the secrets"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name — External Secrets uses it to resolve the Workload Identity binding"
  type        = string
}

variable "cluster_location" {
  description = "Cluster zone or region, as GKE knows it"
  type        = string
}

variable "eso_chart_version" {
  description = "external-secrets chart version — pinned, never a range"
  type        = string
  default     = "2.10.0"
}

variable "eso_namespace" {
  type    = string
  default = "external-secrets"
}

variable "eso_service_account" {
  description = "ESO's Kubernetes service account. Must match the Workload Identity binding in envs/dev exactly."
  type        = string
  default     = "external-secrets"
}

variable "gcp_service_account_email" {
  description = "GCP service account the ESO pod impersonates. Annotated onto the Kubernetes service account — without it the pod authenticates as the node account regardless of any IAM binding."
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace the repo credential Secret must land in — ArgoCD only reads credentials from its own namespace"
  type        = string
  default     = "argocd"
}

variable "secret_store_name" {
  type    = string
  default = "gcp-secret-manager"
}

variable "repo_url" {
  description = "GitOps repository URL. Must match the Applications' repoURL character for character; ArgoCD pairs credentials to repositories by string comparison."
  type        = string
}

variable "ssh_key_secret_name" {
  description = "Secret Manager secret holding the read-only deploy key"
  type        = string
  default     = "argocd-gitops-ssh-key"
}
