resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  instance_name = "${var.name_prefix}-vm-${random_id.suffix.hex}"

  cloud_init = templatefile("${path.module}/scripts/cloud-init.yaml.tftpl", {
    admin_username             = var.admin_username
    ssh_public_key             = var.ssh_public_key
    enable_fail2ban            = var.enable_fail2ban
    enable_unattended_upgrades = var.enable_unattended_upgrades
  })
}

data "vultr_os" "ubuntu" {
  filter {
    name   = "name"
    values = [var.os_name_filter]
  }
}

# --- Firewall -------------------------------------------------------------
# Vultr instances always have a public IPv4 address - this firewall group
# is the only network-layer boundary available (no VPC/NSG-style private
# subnet option here).

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
  notes             = "HTTP for Apache"
}

resource "vultr_firewall_rule" "https" {
  count = length(var.web_source_cidr_blocks)

  firewall_group_id = vultr_firewall_group.this.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = cidrhost(var.web_source_cidr_blocks[count.index], 0)
  subnet_size       = tonumber(split("/", var.web_source_cidr_blocks[count.index])[1])
  port              = "443"
  notes             = "HTTPS for Apache"
}

# --- Compute ------------------------------------------------------------

resource "vultr_instance" "this" {
  label             = local.instance_name
  hostname          = local.instance_name
  region            = var.region
  plan              = var.plan
  os_id             = data.vultr_os.ubuntu.id
  firewall_group_id = vultr_firewall_group.this.id
  enable_ipv6       = var.enable_ipv6
  ddos_protection   = var.enable_ddos_protection
  backups           = var.enable_backups ? "enabled" : "disabled"
  activation_email  = var.activation_email
  user_data         = local.cloud_init
  tags              = concat([var.name_prefix], var.tags)
}
