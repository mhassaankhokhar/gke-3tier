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

  # Same bucket as bootstrap, different prefix. The separation is what stops a
  # destroy here from reaching the pipeline's own identity.
  #
  #   terraform init -backend-config=backend.hcl
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Credentials for the cluster this same configuration creates.
#
# Terraform evaluates provider blocks before it knows what the apply will
# produce, so a provider configured from a resource attribute is the classic
# "provider configuration depends on resource" trap: it works on a second apply
# and fails on the first, and fails again on destroy.
#
# The data sources below break that. They read the cluster by name rather than
# referencing module.gke's attributes, so the reference is to a lookup rather
# than to a resource being created in this run. The cost is that the very first
# apply must create the cluster before these resolve — handled by targeting the
# cluster first, which docs/bootstrap.md spells out.
#
# No depends_on here, deliberately. It was on the cluster lookup once, and it
# quietly reintroduced the very coupling this file exists to avoid:
#
#   depends_on = [module.gke]
#     → Terraform defers the read to apply whenever ANY change is pending in
#       module.gke — a node pool image change is enough
#       → host/token/ca are unknown while the plan refreshes
#         → the helm provider cannot connect, and its read returns "not found"
#           rather than an error
#           → all four releases are recorded as "deleted outside Terraform"
#             → plan says "4 to add"
#               → apply: cannot re-use a name that is still in use
#
# Silent state loss, every time the node pool changed. The failure surfaced two
# node pool edits in a row before the cause was read off the logs: the failing
# run says "will be read during apply", the passing run reads it during plan.
#
# Without depends_on the lookup resolves from the live API at plan time, so the
# provider is configured before anything is refreshed. The only run it cannot
# serve is the one where no cluster exists yet, which is already the targeted
# first apply in docs/bootstrap.md.
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
