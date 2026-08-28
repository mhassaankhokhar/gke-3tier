# Private GKE cluster with two node pools.
#
# The split exists because spot nodes and stateful workloads do not mix. Spot
# VMs are reclaimed on ~30 seconds notice; a CloudNativePG primary or a Longhorn
# replica living on one means constant failover and volume rebuilds. So:
#
#   stateful pool — on-demand, tainted, runs Postgres and Longhorn
#   spot pool     — preemptible, untainted, runs web/api
#
# Stateless replicas absorb preemption fine, and they are the bulk of the
# compute, so most of the cost saving survives the split.

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

# ── Stateful pool: on-demand, tainted ────────────────────────────────────────
resource "google_container_node_pool" "stateful" {
  name     = "${var.name}-stateful"
  cluster  = google_container_cluster.main.id
  location = var.zone

  node_count = var.stateful_node_count

  node_config {
    machine_type = var.stateful_machine_type
    disk_size_gb = var.stateful_disk_size
    disk_type    = "pd-balanced"

    # Longhorn replicates volumes across nodes itself, so the pool must not be
    # autoscaled down underneath it — node_count is fixed for that reason.
    labels = {
      workload = "stateful"
    }

    # Only pods that explicitly tolerate this run here, which keeps web/api off
    # the expensive nodes rather than relying on scheduler luck.
    taint {
      key    = "workload"
      value  = "stateful"
      effect = "NO_SCHEDULE"
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

# ── Stateless pool: spot, autoscaled ─────────────────────────────────────────
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
