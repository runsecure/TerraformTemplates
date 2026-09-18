output "resource_group_name" {
  description = "Name of the resource group holding all resources created by this template."
  value       = azurerm_resource_group.this.name
}

output "vm_id" {
  description = "Resource ID of the Linux VM."
  value       = azurerm_linux_virtual_machine.this.id
}

output "vm_name" {
  description = "Name of the Linux VM."
  value       = azurerm_linux_virtual_machine.this.name
}

output "private_ip_address" {
  description = "Private IP address of the VM's NIC. Use this for Ansible's inventory when the control node has network access to the subnet."
  value       = azurerm_network_interface.this.private_ip_address
}

output "public_ip_address" {
  description = "Public IP address of the VM, if enable_public_ip is true."
  value       = var.enable_public_ip ? azurerm_public_ip.this[0].ip_address : null
}

output "admin_username" {
  description = "SSH username for management (Ansible), authorized via ssh_public_key. Password login is disabled."
  value       = var.admin_username
}

output "network_security_group_id" {
  description = "Resource ID of the NSG protecting the VM's subnet."
  value       = azurerm_network_security_group.this.id
}

output "data_disk_ids" {
  description = "Resource IDs of the additional data disks attached, if any (see the data_disks variable)."
  value       = azurerm_managed_disk.data[*].id
}
