terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Partial backend: the bucket is supplied at init time rather than committed,
  # so this repo names no storage location belonging to a real account — the same
  # reason the project id lives in terraform.tfvars and not in git.
  #
  #   terraform init \
  #     -backend-config="bucket=<your-tfstate-bucket>" \
  #     -backend-config="prefix=gke-3tier/dev"
  #
  # State is remote from the very first apply, including the local bootstrap:
  # the pipeline has to read the state the bootstrap wrote, and a local state
  # file would leave CI unable to see what already exists.
  backend "gcs" {
    # GCS backend locks on the state object itself — no separate lock table, and
    # nothing to provision the way DynamoDB is provisioned for the S3 backend.
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
