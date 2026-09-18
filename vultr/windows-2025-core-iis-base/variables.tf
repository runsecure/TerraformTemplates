variable "name_prefix" {
  description = "Prefix applied to the instance's label/hostname and firewall group."
  type        = string
  default     = "win2025-iis"
}

variable "region" {
  description = "Vultr region code (e.g. ewr = New Jersey, ord = Chicago, lhr = London). See `vultr-cli regions list`."
  type        = string
  default     = "ewr"
}

variable "plan" {
  description = "Vultr plan ID. See `vultr-cli plans list`."
  type        = string
  default     = "vc2-2c-4gb"
}

variable "os_name_filter" {
  description = <<-EOT
    Exact OS catalog name used to look up the Windows Server 2025 image via
    the vultr_os data source. Vultr's catalog naming has historically been
    "Windows <year> x64" (e.g. "Windows 2022 x64"); this repo cannot verify
    the current catalog live. Also verify whether Vultr publishes a Server
    Core (no GUI) variant at all - if not, the closest full Desktop
    Experience image still works with this template (Core vs. Desktop
    doesn't change the IIS/SSH configuration below), you'll just have a GUI
    you didn't strictly need. Check with:
      vultr-cli os list | grep -i windows
  EOT
  type        = string
  default     = "Windows 2025 x64"
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
  description = "CIDR blocks allowed to reach TCP/80 and TCP/443 (IIS). Defaults to the internet since this is a web server."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_public_key" {
  description = "SSH public key (e.g. contents of an id_ed25519.pub) authorized for the admin_username account. Used by Ansible for management; password auth over SSH is disabled."
  type        = string
}

variable "admin_username" {
  description = "Local administrator username on the instance. This account's authorized_keys is used for SSH access."
  type        = string
  default     = "Administrator"
}

variable "admin_password" {
  description = <<-EOT
    Local administrator password, set via the startup script on first
    boot. If left null, a strong random password is generated and stored
    only in Terraform state - protect state accordingly. Day-to-day access
    is via SSH key, not this password; it exists for break-glass console
    access.
  EOT
  type        = string
  default     = null
  sensitive   = true
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
