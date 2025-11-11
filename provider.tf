terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.35"
    }
  }
}

provider "google" {
  # Значення беремо з variables.tf або з env GOOGLE_CLOUD_PROJECT
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
