variable "project_id" {
  description = "GCP project id — also forms the Workload Identity pool name"
  type        = string
}

variable "name" {
  description = "Cluster name and node pool prefix"
  type        = string
}

variable "zone" {
  description = <<-EOT
    Single zone, not a region. A regional cluster replicates the control plane and
    multiplies node count by the number of zones — correct for production, and
    roughly triple the burn rate for a project whose stated goal is to outlive a
    trial credit. The trade-off is that a zone outage takes the cluster down;
    that is an accepted limitation, recorded in docs/.
  EOT
  type        = string
}

variable "network_id" {
  type        = string
  description = "VPC id from the network module"
}

variable "subnet_id" {
  type        = string
  description = "Node subnet id from the network module"
}

variable "pods_range_name" {
  type        = string
  description = "Secondary range name for pods"
}

variable "services_range_name" {
  type        = string
  description = "Secondary range name for services"
}

variable "master_cidr" {
  description = "/28 for the control plane. Must not overlap any other range in the VPC."
  type        = string
  default     = "172.16.0.0/28"
}

variable "authorized_networks" {
  description = <<-EOT
    CIDRs allowed to reach the public control-plane endpoint. Defaults to open
    because a home IP is dynamic and a locked-out cluster is worse than a
    password-protected public endpoint — but narrow this to your own IP when you
    can. Anyone reaching the endpoint still needs valid credentials.
  EOT
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{
    cidr_block   = "0.0.0.0/0"
    display_name = "all (narrow this to your own IP)"
  }]
}

variable "release_channel" {
  description = "REGULAR balances new features against stability; RAPID pushes upgrades faster than a side project wants."
  type        = string
  default     = "REGULAR"
}

variable "node_service_account" {
  description = "Service account for nodes. Leave null for the Compute Engine default, which is over-permissioned — pass a scoped one."
  type        = string
  default     = null
}

# ── Stateful pool ────────────────────────────────────────────────────────────
variable "stateful_machine_type" {
  description = "Runs Postgres and Longhorn. e2-standard-2 is 2 vCPU / 8 GB."
  type        = string
  default     = "e2-standard-2"
}

variable "stateful_node_count" {
  description = "Fixed, not autoscaled: Longhorn replicates across nodes and scale-down would evict replicas. 2 gives Longhorn somewhere to place a second copy."
  type        = number
  default     = 2
}

variable "stateful_image_type" {
  description = <<-EOT
    Node image for the stateful pool. COS_CONTAINERD, the GKE default: Longhorn's
    iscsi requirement is met by its GKE COS node agent rather than by the image,
    and Ubuntu images do not ship open-iscsi either, so switching away buys
    nothing and gives up COS's smaller, better-hardened surface.
  EOT
  type        = string
  default     = "COS_CONTAINERD"
}

variable "stateful_disk_size" {
  description = "GB per stateful node — holds Longhorn replica data as well as the OS"
  type        = number
  default     = 50
}

# ── Spot pool ────────────────────────────────────────────────────────────────
variable "spot_machine_type" {
  description = <<-EOT
    Runs web/api. e2-standard-2 after measuring both, on spot, in this cluster:

      e2-medium        allocatable  940m   agent floor 596m   left  344m
      e2-standard-2    allocatable 1930m   agent floor 730m   left 1200m

    e2-medium is shared-core — Compute Engine reports isSharedCpu: true for it
    and false for e2-standard-2 — so GKE reserves a flat 1060m on it instead of
    the usual 6% + 1%. Both report cpu=2; one delivers 940m and the other 1930m.

    The per-node DaemonSet floor is what makes the difference matter. It is
    nearly fixed, so on the small node it took 63% before an application pod ran
    and there was room for exactly four. Paying half for a quarter of the usable
    capacity is not a saving.

    This replaces an earlier note claiming e2-medium is "1 vCPU / 4 GB" and that
    the small node kept scale-out inside an 8 vCPU quota. Both were wrong: it
    reports 2 vCPU and counts as 2 against E2_CPUS, so the quota arithmetic is
    identical for either type — see spot_max_nodes.
  EOT
  type        = string
  default     = "e2-standard-2"
}

variable "spot_min_nodes" {
  type    = number
  default = 1
}

# E2_CPUS in this region is 8, and every machine here is E2 at 2 vCPU each. The
# stable pool takes 4, so this pool can reach 2 nodes before the quota binds —
# max 3 is a ceiling the quota will not honour. Left as is deliberately: the
# autoscaler simply stops at what it can get, and raising the quota is a request
# to Google rather than a change to this file.
variable "spot_max_nodes" {
  description = "Ceiling for HPA-driven scale-out. Low on purpose — a runaway HPA on a trial credit is a real way to lose it."
  type        = number
  default     = 3
}

variable "spot_disk_size" {
  type    = number
  default = 30
}

variable "probe_pool_enabled" {
  description = <<-EOT
    Creates one spot e2-standard-2 node labelled workload=stateless-probe, to
    measure allocatable on a non-shared-core machine before deciding whether the
    stateless pool should move to it. Nothing schedules onto it but DaemonSets.
    Turn off once the number is recorded.
  EOT
  type        = bool
  default     = false
}
