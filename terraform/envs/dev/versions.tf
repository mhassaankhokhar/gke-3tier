terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }

  # Same bucket as bootstrap, different prefix.
  #   terraform init -backend-config=backend.hcl
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# helm/kubernetes credentials come from a lookup of the cluster by name, not
# from module.gke attributes, so providers are configured at plan time. The
# first apply on an empty state must target module.gke (docs/bootstrap.md).
# No depends_on: it defers the read to apply and the helm releases drop out of state.
data "google_client_config" "default" {}

data "google_container_cluster" "main" {
  name     = var.name
  location = var.zone
  project  = var.project_id
}

locals {
  cluster_host  = "https://${data.google_container_cluster.main.endpoint}"
  cluster_token = data.google_client_config.default.access_token
  cluster_ca    = base64decode(data.google_container_cluster.main.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_host
    token                  = local.cluster_token
    cluster_ca_certificate = local.cluster_ca
  }
}

provider "kubernetes" {
  host                   = local.cluster_host
  token                  = local.cluster_token
  cluster_ca_certificate = local.cluster_ca
}
