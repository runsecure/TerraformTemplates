output "instance_id" {
  description = "Vultr instance ID."
  value       = vultr_instance.this.id
}

output "public_ip_address" {
  description = "Public IPv4 address of the instance. Vultr instances always have one - see the README for why there's no private-only option here."
  value       = vultr_instance.this.main_ip
}

output "admin_username" {
  description = "SSH username for management (Ansible), authorized via ssh_public_key. Password login is disabled."
  value       = var.admin_username
}

output "firewall_group_id" {
  description = "Vultr firewall group protecting the instance."
  value       = vultr_firewall_group.this.id
}

output "data_disk_ids" {
  description = "IDs of the additional Block Storage volumes attached, if any (see the data_disks variable)."
  value       = vultr_block_storage.data[*].id
}
