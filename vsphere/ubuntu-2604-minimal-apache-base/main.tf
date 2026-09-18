resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  vm_name = "${var.name_prefix}-vm-${random_id.suffix.hex}"

  cloud_init = templatefile("${path.module}/scripts/cloud-init.yaml.tftpl", {
    admin_username             = var.admin_username
    ssh_public_key             = var.ssh_public_key
    enable_fail2ban            = var.enable_fail2ban
    enable_unattended_upgrades = var.enable_unattended_upgrades
    additional_mounts          = var.additional_mounts
  })

  cloud_init_metadata = <<-EOT
    instance-id: ${local.vm_name}
    local-hostname: ${local.vm_name}
  EOT

  network_config = var.ipv4_address != null ? templatefile("${path.module}/scripts/network-config.yaml.tftpl", {
    interface_name = var.network_interface_name
    ipv4_address   = var.ipv4_address
    ipv4_prefix    = var.ipv4_prefix_length
    ipv4_gateway   = var.ipv4_gateway
    dns_servers    = var.dns_servers
  }) : null

  guestinfo = merge(
    {
      "guestinfo.userdata"          = base64encode(local.cloud_init)
      "guestinfo.userdata.encoding" = "base64"
      "guestinfo.metadata"          = base64encode(local.cloud_init_metadata)
      "guestinfo.metadata.encoding" = "base64"
    },
    var.ipv4_address != null ? {
      "guestinfo.network-config"          = base64encode(local.network_config)
      "guestinfo.network-config.encoding" = "base64"
    } : {}
  )
}

data "vsphere_datacenter" "this" {
  name = var.datacenter
}

data "vsphere_compute_cluster" "this" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_datastore" "this" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_network" "this" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.this.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.this.id
}

resource "vsphere_virtual_machine" "this" {
  name             = local.vm_name
  resource_pool_id = data.vsphere_compute_cluster.this.resource_pool_id
  datastore_id     = data.vsphere_datastore.this.id
  folder           = var.folder

  num_cpus = var.num_cpus
  memory   = var.memory_mb

  guest_id  = data.vsphere_virtual_machine.template.guest_id
  scsi_type = data.vsphere_virtual_machine.template.scsi_type
  firmware  = data.vsphere_virtual_machine.template.firmware

  network_interface {
    network_id   = data.vsphere_network.this.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = coalesce(var.disk_size_gb, data.vsphere_virtual_machine.template.disks[0].size)
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks[0].eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned
  }

  # Additional data disks - formatted (ext4) and mounted under /mnt/dataN
  # by cloud-init. unit_number skips 7 (reserved for the SCSI controller
  # itself), which only matters once you're attaching 7+ data disks on a
  # single controller.
  dynamic "disk" {
    for_each = var.data_disks
    content {
      label       = "disk${disk.key + 1}"
      unit_number = disk.key + 1
      size        = disk.value.size_gb
    }
  }

  # No vsphere `clone.customize` block here on purpose - Linux guest
  # customization is handled by cloud-init reading the VMware guestinfo
  # datasource below instead, which is the current recommended approach
  # for cloud-init-enabled Linux templates on vSphere.
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  extra_config = local.guestinfo
}
