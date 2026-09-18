resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  vm_name = "${var.name_prefix}-vm-${random_id.suffix.hex}"
  # Windows computer names are capped at 15 characters; name_prefix can be
  # arbitrarily long, so derive a short, guaranteed-unique hostname instead
  # of using vm_name directly.
  computer_name = "vm-${random_id.suffix.hex}"

  admin_password = coalesce(var.admin_password, try(random_password.admin[0].result, null))

  bootstrap_script = templatefile("${path.module}/scripts/bootstrap.ps1.tftpl", {
    ssh_public_key = var.ssh_public_key
  })
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

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      windows_options {
        computer_name  = local.computer_name
        admin_password = local.admin_password
        workgroup      = "WORKGROUP"
        time_zone      = var.windows_time_zone

        # Runs once, after sysprep guest customization completes. This is
        # the on-prem equivalent of Azure's CustomScriptExtension / AWS &
        # GCP's Windows startup-script metadata - same bootstrap script,
        # same -EncodedCommand trick to survive the registry/RunOnce
        # command line intact.
        run_once_command_list = [
          "powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(local.bootstrap_script, "UTF-16LE")}"
        ]
      }

      network_interface {
        ipv4_address = var.ipv4_address
        ipv4_netmask = var.ipv4_prefix_length
      }

      ipv4_gateway    = var.ipv4_gateway
      dns_server_list = var.dns_server_list
    }
  }
}
