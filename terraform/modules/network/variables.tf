variable "name" {
  description = "Name prefix for network resources"
  type        = string
}

variable "region" {
  description = "GCP region for the subnet, router and NAT"
  type        = string
}

variable "node_cidr" {
  description = "Primary range — node IPs. /24 leaves room for far more nodes than this cluster will ever run."
  type        = string
  default     = "10.10.0.0/24"
}

variable "pod_cidr" {
  description = <<-EOT
    Secondary range for pods. GKE allocates a /24 per node by default (256 pod
    IPs), so a /16 supports 256 nodes. Cannot be changed without recreating the
    cluster, which is why it is oversized rather than tight.
  EOT
  type        = string
  default     = "10.20.0.0/16"
}

variable "service_cidr" {
  description = "Secondary range for ClusterIP services. /20 is 4096 services — far more than this cluster needs, and equally unchangeable later."
  type        = string
  default     = "10.30.0.0/20"
}
