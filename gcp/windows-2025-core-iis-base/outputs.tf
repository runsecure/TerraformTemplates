output "instance_id" {
  description = "GCE instance ID."
  value       = google_compute_instance.this.instance_id
}

output "instance_name" {
  description = "GCE instance name."
  value       = google_compute_instance.this.name
}

output "network_id" {
  description = "VPC network ID created for this deployment."
  value       = google_compute_network.this.id
}

output "private_ip_address" {
  description = "Private IP address of the instance. Use this for Ansible's inventory when the control node has network access to the subnet."
  value       = google_compute_instance.this.network_interface[0].network_ip
}

output "public_ip_address" {
  description = "Static external IP address of the instance, if enable_public_ip is true."
  value       = var.enable_public_ip ? google_compute_address.this[0].address : null
}

output "admin_username" {
  description = "Local administrator / SSH username."
  value       = var.admin_username
}

output "admin_password" {
  description = "Local administrator password (generated if admin_password was not supplied). Only used for break-glass console access - day-to-day management is via SSH key."
  value       = local.admin_password
  sensitive   = true
}
