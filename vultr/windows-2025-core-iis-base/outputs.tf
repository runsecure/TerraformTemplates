output "instance_id" {
  description = "Vultr instance ID."
  value       = vultr_instance.this.id
}

output "public_ip_address" {
  description = "Public IPv4 address of the instance. Vultr instances always have one - see the README for why there's no private-only option here."
  value       = vultr_instance.this.main_ip
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

output "firewall_group_id" {
  description = "Vultr firewall group protecting the instance."
  value       = vultr_firewall_group.this.id
}
