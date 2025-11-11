resource "google_compute_network" "vpc" {
  name                    = "mvp-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "mvp-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.network_cidr
}
