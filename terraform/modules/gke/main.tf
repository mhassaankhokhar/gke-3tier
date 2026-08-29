# Private GKE cluster with two node pools.
#
# The split exists because spot nodes and stateful workloads do not mix. Spot
# VMs are reclaimed on ~30 seconds notice; a CloudNativePG primary or a Longhorn
# replica living on one means constant failover and volume rebuilds. So:
#
#   stateful pool — on-demand, runs Postgres and Longhorn
#   spot pool     — preemptible, runs web/api
#
# Stateless replicas absorb preemption fine, and they are the bulk of the
# compute, so most of the cost saving survives the split.
#
# Placement is by LABEL, not by taint. The stateful pool was tainted
# NoSchedule at first, and that pushed every GKE system pod — kube-dns,
# metrics-server, konnectivity — onto the spot nodes, because none of them
# tolerate a custom taint. Two consequences, both bad: cluster DNS ended up on
# preemptible hardware, and the spot pool needed a second node purely for system
# overhead before any application was deployed.
#
# So neither pool is tainted. Workloads that must land somewhere specific say so
# themselves via nodeSelector on the workload label — which also puts the
# scheduling decision in the manifest, where it is visible, instead of in a node
# pool property nobody reads.

resource "google_container_cluster" "main" {
  name     = var.name
  location = var.zone # zonal, not regional — see variables.tf

  network    = var.network_id
  subnetwork = var.subnet_id

  # GKE insists on a default pool at create time; both real pools are managed as
  # separate resources so their settings can change without cluster replacement.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Lets pods authenticate as GCP service accounts without a downloaded key —
  # the same "no stored credentials" posture the CI pipeline uses.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes = true
    # The control plane keeps a public endpoint: a private endpoint would need a
    # bastion or VPN to reach kubectl from a laptop, which is real production
    # practice but pure friction for a single-operator project. Access is
    # restricted by master_authorized_networks below instead.
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }

  # Off on purpose: this cluster runs its own kube-prometheus-stack, and GKE's
  # managed collection bills per sample on top of it.
  monitoring_config {
    enable_components = []
    managed_prometheus {
      enabled = false
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  # A trial-credit cluster should be destroyable. The default protection turns
  # `terraform destroy` into a manual console step.
  deletion_protection = false
}

# ── Stateful pool: on-demand, labelled workload=stateful ─────────────────────
resource "google_container_node_pool" "stateful" {
  name     = "${var.name}-stateful"
  cluster  = google_container_cluster.main.id
  location = var.zone

  node_count = var.stateful_node_count

  node_config {
    machine_type = var.stateful_machine_type
    disk_size_gb = var.stateful_disk_size
    disk_type    = "pd-balanced"

    # Container-Optimized OS on both pools.
    #
    # Longhorn needs iscsiadm and the iscsi_tcp module on the host. Neither GKE
    # image provides them: Longhorn's docs recommend Ubuntu on GKE "since it
    # contains open-iscsi already", but on a GKE Ubuntu 24.04 node it does not —
    # `kubectl debug node/... -- chroot /host which iscsiadm` finds nothing. The
    # documentation is stale, so switching images buys nothing and gives up COS's
    # smaller, better-hardened surface.
    #
    # The requirement is met instead by Longhorn's GKE COS node agent, deployed
    # from the GitOps repo, which loads the kernel module and runs iscsid in a
    # container.
    image_type = var.stateful_image_type

    # Longhorn replicates volumes across nodes itself, so the pool must not be
    # autoscaled down underneath it — node_count is fixed for that reason.
    labels = {
      workload = "stateful"

      # Which nodes Longhorn may put replica data on.
      #
      # longhorn-manager runs on every node, because Longhorn refuses to attach
      # a volume to a node it has not registered — including an RWX volume,
      # whose client only mounts NFS. Pinning the manager to this pool made the
      # spot pool unable to mount anything at all:
      #
      #   FailedAttachVolume: node.longhorn.io "gke-...-spot-..." not found
      #
      # So placement moves down a level: manager everywhere, disks only here.
      # With create-default-disk-labeled-nodes enabled, Longhorn creates a
      # default disk only on nodes carrying this label, and a node with no disk
      # can mount volumes but can never host a replica. That is the property
      # the manager's nodeSelector was standing in for, expressed where it
      # actually belongs.
      "node.longhorn.io/create-default-disk" = "true"
    }

    service_account = var.node_service_account
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# ── Stateless pool: spot, autoscaled, labelled workload=stateless ────────────
resource "google_container_node_pool" "spot" {
  name     = "${var.name}-spot"
  cluster  = google_container_cluster.main.id
  location = var.zone

  autoscaling {
    min_node_count = var.spot_min_nodes
    max_node_count = var.spot_max_nodes
  }

  node_config {
    machine_type = var.spot_machine_type
    disk_size_gb = var.spot_disk_size
    disk_type    = "pd-balanced"
    spot         = true

    labels = {
      workload = "stateless"
    }

    service_account = var.node_service_account
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
