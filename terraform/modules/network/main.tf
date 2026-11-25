# VPC for a private GKE cluster. Nodes have no public IPs, so egress goes
# through Cloud NAT; without it image pulls time out.

resource "google_compute_network" "vpc" {
  name = "${var.name}-vpc"
  # Custom mode: GKE's secondary ranges are declared explicitly.
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "nodes" {
  name          = "${var.name}-nodes"
  network       = google_compute_network.vpc.id
  region        = var.region
  ip_cidr_range = var.node_cidr

  # VPC-native. Sized generously: these ranges can't be resized, only replaced with the cluster.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pod_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.service_cidr
  }

  # Google APIs over internal addressing, not through the NAT.
  private_ip_google_access = true
}

resource "google_compute_router" "router" {
  name    = "${var.name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Errors only: full NAT logging bills as log ingestion.
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
