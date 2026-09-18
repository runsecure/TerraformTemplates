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
  description = "SSH username for management (Ansible), authorized via ssh_public_key. Password login is disabled."
  value       = var.admin_username
}

output "security_group_id" {
  description = "Security group protecting the instance."
  value       = aws_security_group.this.id
}
