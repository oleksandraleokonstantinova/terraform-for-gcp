resource "google_compute_health_check" "hc" {
  name = "mvp-hc"
  http_health_check {
    port = 80
  }
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2
}

resource "google_compute_backend_service" "backend" {
  name                  = "mvp-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.hc.id]
  timeout_sec           = 30

  backend {
    group          = google_compute_instance_group.uig.id
    balancing_mode = "UTILIZATION"
  }
}

resource "google_compute_url_map" "urlmap" {
  name            = "mvp-urlmap"
  default_service = google_compute_backend_service.backend.id
}

resource "google_compute_target_http_proxy" "proxy" {
  name    = "mvp-proxy"
  url_map = google_compute_url_map.urlmap.id
}

resource "google_compute_global_forwarding_rule" "fw_rule" {
  name                  = "mvp-http-forwarding-rule"
  target                = google_compute_target_http_proxy.proxy.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
}