resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  instance_name  = "${var.name_prefix}-vm-${random_id.suffix.hex}"
  admin_password = coalesce(var.admin_password, try(random_password.admin[0].result, null))

  bootstrap_script_body = templatefile("${path.module}/scripts/bootstrap.ps1.tftpl", {
    ssh_public_key         = var.ssh_public_key
    admin_password         = local.admin_password
    additional_mounts_json = jsonencode(var.additional_mounts)
  })

  # Cloudbase-Init (Vultr's Windows guest agent) only executes user_data as
  # a PowerShell script when it starts with this exact marker line.
  bootstrap_script = "#ps1_sysnative\n${local.bootstrap_script_body}"
}

resource "random_password" "admin" {
  count = var.admin_password == null ? 1 : 0

  length      = 24
  special     = true
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
  # Windows local account passwords reject some special characters.
  override_special = "!#%&*+-.:=?@^_"
}

data "vultr_os" "windows" {
  filter {
    name   = "name"
    values = [var.os_name_filter]
  }
}

# --- Firewall -------------------------------------------------------------
# Vultr instances always have a public IPv4 address - this firewall group
# is the only network-layer boundary available (no VPC/NSG-style private
# subnet option here). No RDP/WinRM rule is defined anywhere.

resource "vultr_firewall_group" "this" {
  description = "${var.name_prefix}-fw"
}

resource "vultr_firewall_rule" "ssh" {
  count = length(var.admin_source_cidr_blocks)

  firewall_group_id = vultr_firewall_group.this.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = cidrhost(var.admin_source_cidr_blocks[count.index], 0)
  subnet_size       = tonumber(split("/", var.admin_source_cidr_blocks[count.index])[1])
  port              = "22"
  notes             = "SSH from admin allow-list"
}

resource "vultr_firewall_rule" "http" {
  count = length(var.web_source_cidr_blocks)

  firewall_group_id = vultr_firewall_group.this.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = cidrhost(var.web_source_cidr_blocks[count.index], 0)
  subnet_size       = tonumber(split("/", var.web_source_cidr_blocks[count.index])[1])
  port              = "80"
  notes             = "HTTP for IIS"
}

resource "vultr_firewall_rule" "https" {
  count = length(var.web_source_cidr_blocks)

  firewall_group_id = vultr_firewall_group.this.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = cidrhost(var.web_source_cidr_blocks[count.index], 0)
  subnet_size       = tonumber(split("/", var.web_source_cidr_blocks[count.index])[1])
  port              = "443"
  notes             = "HTTPS for IIS"
}

# --- Compute ------------------------------------------------------------

resource "vultr_instance" "this" {
  label             = local.instance_name
  hostname          = local.instance_name
  region            = var.region
  plan              = var.plan
  os_id             = data.vultr_os.windows.id
  firewall_group_id = vultr_firewall_group.this.id
  enable_ipv6       = var.enable_ipv6
  ddos_protection   = var.enable_ddos_protection
  backups           = var.enable_backups ? "enabled" : "disabled"
  activation_email  = var.activation_email
  user_data         = local.bootstrap_script
  tags              = concat([var.name_prefix], var.tags)
}

# Additional Block Storage volumes - initialized, brought online, and
# formatted by the bootstrap script (see scripts/bootstrap.ps1.tftpl).
resource "vultr_block_storage" "data" {
  count = length(var.data_disks)

  region               = var.region
  size_gb              = var.data_disks[count.index].size_gb
  label                = "${var.name_prefix}-data-${count.index}"
  attached_to_instance = vultr_instance.this.id
}
