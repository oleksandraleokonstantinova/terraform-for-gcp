# compute.tf

resource "google_compute_instance" "vm" {
  count        = 2
  name         = "mvp-vm-${count.index + 1}"
  machine_type = "e2-micro"
  zone         = var.zone

  tags = ["mvp-web"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.self_link
    access_config {} # external IP
  }

  metadata_startup_script = file("${path.module}/startup.sh")
}

# Unmanaged Instance Group з двох VM
resource "google_compute_instance_group" "uig" {
  name = "mvp-uig"
  zone = var.zone

  instances = [
    for i in google_compute_instance.vm : i.self_link
  ]

  named_port {
    name = "http"
    port = 80
  }
}