# Terraform & Provider
############################################
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.35"
    }
  }
}

# Заповни за потреби. Якщо вже експортував GOOGLE_CLOUD_PROJECT,
# то provider прочитає project з env і цей var можна не задавати.
variable "project_id" {
  type    = string
  default = null
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "network_cidr" {
  type    = string
  default = "10.10.0.0/24"
}


provider "google" {
  project = var.project_id # можна лишити null — буде з env
  region  = var.region
  zone    = var.zone
}

locals {
  name_prefix = "mvp"
  vpc_name    = "${local.name_prefix}-vpc"
  subnet_name = "${local.name_prefix}-subnet"
}

############################################
# Enable required APIs (не відключаємо при destroy)
############################################
resource "google_project_service" "serviceusage" {
  service            = "serviceusage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudapis" {
  service            = "cloudapis.googleapis.com"
  disable_on_destroy = false
  depends_on         = [google_project_service.serviceusage]
}

resource "google_project_service" "resman" {
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
  depends_on         = [google_project_service.cloudapis]
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
  depends_on         = [google_project_service.resman]
}

############################################
# Network
############################################
resource "google_compute_network" "vpc" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute]
}

resource "google_compute_subnetwork" "subnet" {
  name          = local.subnet_name
  ip_cidr_range = var.network_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Firewall: SSH
resource "google_compute_firewall" "allow-ssh" {
  name    = "${local.name_prefix}-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh"]
}

# Firewall: HTTP
resource "google_compute_firewall" "allow-http" {
  name    = "${local.name_prefix}-allow-http"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

############################################
# 2 x VM (із надійним startup script для nginx)
############################################
# Спільний скрипт (apt з ретраями, тест служби)
locals {
  startup_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive

    retry() { 
      local n=0
      until "$@"; do 
        n=$((n+1))
        [ $n -ge 10 ] && { echo "FAILED: $*"; exit 1; }
        sleep 3
      done
    }

    # Update & install nginx
    retry apt-get update
    retry apt-get install -y nginx

    systemctl enable nginx
    systemctl restart nginx || true

    # Simple page with hostname
    cat >/var/www/html/index.html <<HTML
    <html>
      <head><title>GCP MVP</title></head>
      <body style="font-family:Arial; text-align:center">
        <h1>It works!</h1>
        <p>Served by: $(hostname)</p>
      </body>
    </html>
    HTML

    # Ensure port 80 is listening
    ss -lntp | grep ':80' || { echo "nginx not listening"; systemctl status nginx --no-pager; exit 1; }
  EOT

  
  startup_script_lf = replace(local.startup_script, "\r\n", "\n")
}


resource "google_compute_instance" "vm1" {
  name         = "${local.name_prefix}-vm-1"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.name
    # ephemeral external ip
    access_config {}
  }

  tags = ["web", "ssh"]

  metadata_startup_script = local.startup_script

  depends_on = [
    google_compute_firewall.allow-http,
    google_compute_firewall.allow-ssh
  ]
}

resource "google_compute_instance" "vm2" {
  name         = "${local.name_prefix}-vm-2"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {}
  }

  tags = ["web", "ssh"]

  metadata_startup_script = local.startup_script

  depends_on = [
    google_compute_firewall.allow-http,
    google_compute_firewall.allow-ssh
  ]
}

############################################
# Instance Group (unmanaged) + Health Check
############################################
resource "google_compute_instance_group" "uig" {
  name = "${local.name_prefix}-uig"
  zone = var.zone

  instances = [
    google_compute_instance.vm1.self_link,
    google_compute_instance.vm2.self_link
  ]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_health_check" "hc" {
  name               = "${local.name_prefix}-hc"
  check_interval_sec = 5
  timeout_sec        = 5

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

############################################
# Backend Service → URL Map → HTTP Proxy → Global Forwarding Rule
############################################
resource "google_compute_backend_service" "backend" {
  name                  = "${local.name_prefix}-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.hc.id]

  backend {
    group = google_compute_instance_group.uig.self_link
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_url_map" "urlmap" {
  name            = "${local.name_prefix}-urlmap"
  default_service = google_compute_backend_service.backend.id
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "${local.name_prefix}-http-proxy"
  url_map = google_compute_url_map.urlmap.id
}

resource "google_compute_global_forwarding_rule" "fw_rule" {
  name       = "${local.name_prefix}-http-forwarding-rule"
  target     = google_compute_target_http_proxy.http_proxy.id
  port_range = "80"
}

############################################
# Outputs
############################################
output "load_balancer_ip" {
  value       = google_compute_global_forwarding_rule.fw_rule.ip_address
  description = "External IP of the HTTP load balancer"
}

output "vm1_ip" {
  value       = google_compute_instance.vm1.network_interface[0].access_config[0].nat_ip
  description = "VM1 external IP"
}

output "vm2_ip" {
  value       = google_compute_instance.vm2.network_interface[0].access_config[0].nat_ip
  description = "VM2 external IP"
}