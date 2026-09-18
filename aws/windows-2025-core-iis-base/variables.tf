variable "name_prefix" {
  description = "Prefix applied to all resource names/tags created by this template."
  type        = string
  default     = "win2025-iis"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags applied to every resource created by this template."
  type        = map(string)
  default     = {}
}

# --- Networking -------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC created by this template."
  type        = string
  default     = "10.60.0.0/24"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet the instance is launched into."
  type        = string
  default     = "10.60.0.0/26"
}

variable "nat_subnet_cidr" {
  description = "CIDR block for the small dedicated subnet used to host the NAT gateway, when enable_nat_gateway is true and enable_public_ip is false."
  type        = string
  default     = "10.60.0.64/28"
}

variable "enable_public_ip" {
  description = <<-EOT
    Whether to attach a static Elastic IP to the instance and route its
    subnet directly to an internet gateway. Leave this false (default) for
    a fully private instance reached over SSH via a jumpbox/VPN and managed
    by Ansible over a private network. Only enable this for lab/demo
    scenarios where admin_source_cidr_blocks is tightly scoped - the web
    ports are internet-facing by default (web_source_cidr_blocks) once a
    public IP exists.
  EOT
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Whether to provision a NAT gateway (in its own small public subnet) so
    the instance still has outbound internet access when enable_public_ip
    is false. This is required for the bootstrap script's
    Add-WindowsCapability (OpenSSH) call to succeed unless your VPC already
    provides egress some other way (Transit Gateway, existing NAT, etc).
    A NAT gateway has an hourly charge plus per-GB data processing charges -
    set this to false if you already have egress via another path, or if
    enable_public_ip is true (in which case this is ignored).
  EOT
  type        = bool
  default     = true
}

variable "admin_source_cidr_blocks" {
  description = <<-EOT
    CIDR blocks allowed to reach TCP/22 (SSH) on the instance, e.g. your
    Ansible control node(s) or management VPN range. Must be explicitly
    set - there is no default - so nobody accidentally opens SSH to the
    world.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.admin_source_cidr_blocks) > 0
    error_message = "admin_source_cidr_blocks must contain at least one CIDR block; it is not allowed to default open."
  }
}

variable "web_source_cidr_blocks" {
  description = "CIDR blocks allowed to reach TCP/80 and TCP/443 (IIS). Defaults to the internet since this is a web server. Only reachable at all once enable_public_ip is true."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Compute ------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 50
}

variable "ami_owners" {
  description = "Owner filter for the AMI lookup."
  type        = list(string)
  default     = ["amazon"]
}

variable "ami_name_filter" {
  description = <<-EOT
    Name filter used to look up the Windows Server 2025 Core AMI. Verify
    this matches an available AMI in your region before applying, e.g.:
      aws ec2 describe-images --owners amazon \
        --filters "Name=name,Values=Windows_Server-2025-English-Core-Base-*" \
        --query 'Images[].Name' --region <region>
  EOT
  type        = string
  default     = "Windows_Server-2025-English-Core-Base-*"
}

variable "admin_username" {
  description = "Local administrator username on the instance. This account's authorized_keys is used for SSH access."
  type        = string
  default     = "Administrator"
}

variable "admin_password" {
  description = <<-EOT
    Local administrator password, set via user-data on first boot. If left
    null, a strong random password is generated and stored only in
    Terraform state - protect state accordingly (remote state with
    encryption + access control), or supply your own password sourced from
    a secrets manager (e.g. AWS Secrets Manager). Day-to-day access is via
    SSH key, not this password; it exists for break-glass console access.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key (e.g. contents of an id_ed25519.pub) authorized for the admin_username account. Used by Ansible for management; password auth over SSH is disabled."
  type        = string
}
