# VPC for a private GKE cluster.
#
# Nodes get no public IPs, so egress (image pulls, OS updates, Longhorn
# components) has to leave through Cloud NAT. Without the NAT below, a private
# cluster comes up and then fails every image pull with a timeout that looks
# like a registry problem rather than a networking one.

resource "google_compute_network" "vpc" {
  name = "${var.name}-vpc"
  # Custom mode: auto mode creates a subnet in every region with ranges we do not
  # control, and the secondary ranges GKE needs have to be declared explicitly
  # anyway.
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "nodes" {
  name          = "${var.name}-nodes"
  network       = google_compute_network.vpc.id
  region        = var.region
  ip_cidr_range = var.node_cidr

  # VPC-native cluster: pods and services get real routable ranges instead of
  # being hidden behind node IPs. Sized generously on purpose — these ranges
  # cannot be resized later, only replaced by recreating the cluster.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pod_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.service_cidr
  }

  # Lets private nodes reach Google APIs (Artifact Registry, and GCS for the
  # database backups) over internal addressing rather than out through the NAT.
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

  # Errors only: full NAT logging is chatty and bills as log ingestion, which
  # matters when the whole point is to make a trial credit last.
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
