variable "name_prefix" {
  description = "Prefix applied to the instance's label/hostname and firewall group."
  type        = string
  default     = "ubuntu2604-apache"
}

variable "region" {
  description = "Vultr region code (e.g. ewr = New Jersey, ord = Chicago, lhr = London). See `vultr-cli regions list`."
  type        = string
  default     = "ewr"
}

variable "plan" {
  description = "Vultr plan ID. See `vultr-cli plans list`."
  type        = string
  default     = "vc2-1c-2gb"
}

variable "os_name_filter" {
  description = <<-EOT
    Exact OS catalog name used to look up the Ubuntu 26.04 image via the
    vultr_os data source. This repo cannot verify the current catalog
    live - check with:
      vultr-cli os list | grep -i ubuntu
    If 26.04 isn't published yet, fall back to "Ubuntu 24.04 LTS x64".
  EOT
  type        = string
  default     = "Ubuntu 26.04 LTS x64"
}

variable "admin_source_cidr_blocks" {
  description = <<-EOT
    CIDR blocks allowed to reach TCP/22 (SSH) on the instance, e.g. your
    Ansible control node(s) or management VPN range. Must be explicitly
    set - there is no default - so nobody accidentally opens SSH to the
    world. Unlike the hyperscaler templates in this repo, Vultr instances
    always get a public IPv4 address - there is no "private, no public IP"
    option here, so this firewall group is the only thing standing between
    the instance and the internet.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.admin_source_cidr_blocks) > 0
    error_message = "admin_source_cidr_blocks must contain at least one CIDR block; it is not allowed to default open."
  }
}

variable "web_source_cidr_blocks" {
  description = "CIDR blocks allowed to reach TCP/80 and TCP/443 (Apache). Defaults to the internet since this is a web server."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_public_key" {
  description = "SSH public key (e.g. contents of an id_ed25519.pub) authorized for admin_username. Used by Ansible for management; password auth is disabled."
  type        = string
}

variable "admin_username" {
  description = "SSH username created on the instance via cloud-init."
  type        = string
  default     = "ansible"
}

variable "enable_ipv6" {
  description = "Enable IPv6 on the instance. Left false by default to keep the exposed surface to a single stack, matching the other templates."
  type        = bool
  default     = false
}

variable "enable_ddos_protection" {
  description = "Enable Vultr's DDoS protection add-on. Incurs additional cost."
  type        = bool
  default     = false
}

variable "enable_backups" {
  description = "Enable Vultr's automatic backups add-on. Incurs additional cost."
  type        = bool
  default     = false
}

variable "activation_email" {
  description = "Whether Vultr sends an activation/ready email for this instance. Left false by default for automation-driven deployments."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the instance."
  type        = list(string)
  default     = []
}

variable "enable_fail2ban" {
  description = "Install and enable fail2ban to mitigate SSH brute-force attempts."
  type        = bool
  default     = true
}

variable "enable_unattended_upgrades" {
  description = "Install and enable unattended-upgrades for automatic security patching."
  type        = bool
  default     = true
}
