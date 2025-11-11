# SSH: дозволяємо тільки з моєї IP
resource "google_compute_firewall" "allow_ssh" {
  name    = "mvp-allow-ssh"
  network = google_compute_network.vpc.name

  source_ranges = [var.ssh_allowed_cidr]
  target_tags   = ["mvp-web"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# HTTP: тільки з GFE + Health-checks (GCP)
resource "google_compute_firewall" "allow_http_from_gfe" {
  name    = "mvp-allow-http-from-gfe"
  network = google_compute_network.vpc.name

  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]
  target_tags = ["mvp-web"]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}