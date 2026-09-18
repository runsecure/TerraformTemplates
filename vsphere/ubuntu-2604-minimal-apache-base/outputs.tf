output "vm_id" {
  description = "vSphere managed object ID of the VM."
  value       = vsphere_virtual_machine.this.id
}

output "vm_name" {
  description = "Name of the VM in vCenter."
  value       = vsphere_virtual_machine.this.name
}

output "ip_address" {
  description = "IP address reported by VMware Tools once the guest is up (static, if configured; otherwise DHCP-assigned)."
  value       = vsphere_virtual_machine.this.default_ip_address
}

output "admin_username" {
  description = "SSH username for management (Ansible), authorized via ssh_public_key. Password login is disabled."
  value       = var.admin_username
}
