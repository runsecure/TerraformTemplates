output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "vpc_id" {
  description = "VPC ID created for this deployment."
  value       = aws_vpc.this.id
}

output "private_ip_address" {
  description = "Private IP address of the instance. Use this for Ansible's inventory when the control node has network access to the subnet."
  value       = aws_instance.this.private_ip
}

output "public_ip_address" {
  description = "Elastic IP address of the instance, if enable_public_ip is true."
  value       = var.enable_public_ip ? aws_eip.this[0].public_ip : null
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

output "security_group_id" {
  description = "Security group protecting the instance."
  value       = aws_security_group.this.id
}

output "data_disk_ids" {
  description = "EBS volume IDs of the additional data disks attached, if any (see the data_disks variable)."
  value       = aws_ebs_volume.data[*].id
}
