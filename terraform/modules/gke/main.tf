# Private zonal GKE cluster with two node pools: on-demand "stateful" for Postgres
# and Longhorn, spot "stateless" for web/api. Pools are selected by the
# workload label, not taints: a taint pushes GKE system pods (kube-dns etc.) onto spot.

resource "google_container_cluster" "main" {
  name     = var.name
  location = var.zone # zonal, not regional — see variables.tf

  network    = var.network_id
  subnetwork = var.subnet_id

  # GKE requires a default pool at create time; the real pools are separate
  # resources so they can change without replacing the cluster.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Pods authenticate as GCP service accounts without key files.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Dataplane V2: enforces NetworkPolicy natively (no Calico). Literal, not a
  # variable: changing it replaces the cluster (see docs/bootstrap.md, first apply).
  datapath_provider = "ADVANCED_DATAPATH"

  private_cluster_config {
    enable_private_nodes = true
    # Public endpoint, restricted by master_authorized_networks: a private one
    # would need a bastion or VPN for kubectl.
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

  # Off: the cluster runs its own kube-prometheus-stack; managed collection bills per sample.
  monitoring_config {
    enable_components = []
    managed_prometheus {
      enabled = false
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  # Destroyable without a console step.
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

    # COS on both pools. Longhorn's iscsi requirement is met by its GKE COS node
    # agent (GitOps repo); GKE's Ubuntu image lacks iscsiadm too.
    image_type = var.stateful_image_type

    # Fixed node_count: Longhorn replicates across these nodes and must not be scaled down under.
    labels = {
      workload = "stateful"

      # Longhorn creates replica disks only on nodes with this label
      # (create-default-disk-labeled-nodes); longhorn-manager still runs everywhere
      # so spot nodes can mount volumes.
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

# ── Probe pool: off by default (probe_pool_enabled) ──────────────────────────
# Measured allocatable CPU on spot e2-standard-2. Labelled stateless-probe so no
# app pod selects it. Remove once no longer needed.
resource "google_container_node_pool" "probe" {
  count = var.probe_pool_enabled ? 1 : 0

  name       = "${var.name}-probe"
  cluster    = google_container_cluster.main.id
  location   = var.zone
  node_count = 1

  node_config {
    machine_type = "e2-standard-2"
    disk_size_gb = var.spot_disk_size
    disk_type    = "pd-balanced"
    spot         = true

    labels = {
      workload = "stateless-probe"
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
