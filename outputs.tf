output "load_balancer_ip" {
  description = "External IP of Global HTTP Load Balancer (A-record target)"
  value       = google_compute_global_forwarding_rule.fw_rule.ip_address
}

# Зовнішні IP обох VM (зручно для дебагу/SSH)
output "vm_ips" {
  description = "External IPs of the VMs"
  value       = [for i in google_compute_instance.vm : i.network_interface[0].access_config[0].nat_ip]
}

# URL групи інстансів, до якої підʼєднаний бекенд
output "instance_group" {
  description = "Unmanaged Instance Group self link"
  value       = google_compute_instance_group.uig.self_link
}
