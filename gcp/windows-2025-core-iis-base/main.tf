resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  network_tag    = "${var.name_prefix}-vm"
  admin_password = coalesce(var.admin_password, try(random_password.admin[0].result, null))

  # A custom machine type (independent vCPU/memory dialing) overrides
  # machine_type entirely when both custom_cpu_count and custom_memory_mb
  # are set.
  machine_type = (
    var.custom_cpu_count != null && var.custom_memory_mb != null
    ? "custom-${var.custom_cpu_count}-${var.custom_memory_mb}"
    : var.machine_type
  )

  bootstrap_script = templatefile("${path.module}/scripts/bootstrap.ps1.tftpl", {
    ssh_public_key         = var.ssh_public_key
    admin_password         = local.admin_password
    additional_mounts_json = jsonencode(var.additional_mounts)
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

data "google_compute_image" "windows" {
  family  = var.image_family
  project = var.image_project
}

# --- Networking -------------------------------------------------------------

resource "google_compute_network" "this" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  name          = "${var.name_prefix}-subnet"
  network       = google_compute_network.this.id
  region        = var.region
  ip_cidr_range = var.subnet_cidr
}

# Custom-mode VPCs deny all ingress by default - only what's explicitly
# allowed below is reachable. No RDP/WinRM rule is defined anywhere.

resource "google_compute_firewall" "ssh" {
  name    = "${var.name_prefix}-allow-ssh"
  network = google_compute_network.this.id

  direction     = "INGRESS"
  target_tags   = [local.network_tag]
  source_ranges = var.admin_source_cidr_ranges

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "web" {
  name    = "${var.name_prefix}-allow-web"
  network = google_compute_network.this.id

  direction     = "INGRESS"
  target_tags   = [local.network_tag]
  source_ranges = var.web_source_cidr_ranges

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_address" "this" {
  count = var.enable_public_ip ? 1 : 0

  name   = "${var.name_prefix}-ip"
  region = var.region
}

# --- Compute ------------------------------------------------------------

# Additional data disks - initialized, brought online, and formatted by
# the bootstrap script (see scripts/bootstrap.ps1.tftpl).
resource "google_compute_disk" "data" {
  count = length(var.data_disks)

  name = "${var.name_prefix}-data-${count.index}"
  zone = var.zone
  type = var.data_disks[count.index].type
  size = var.data_disks[count.index].size_gb
}

resource "google_compute_instance" "this" {
  name         = "${var.name_prefix}-vm-${random_id.suffix.hex}"
  machine_type = local.machine_type
  zone         = var.zone
  tags         = [local.network_tag]
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = data.google_compute_image.windows.self_link
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
  }

  dynamic "attached_disk" {
    for_each = google_compute_disk.data
    content {
      source = attached_disk.value.self_link
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.this.id

    dynamic "access_config" {
      for_each = var.enable_public_ip ? [1] : []
      content {
        nat_ip = google_compute_address.this[0].address
      }
    }
  }

  metadata = {
    windows-startup-script-ps1 = local.bootstrap_script
  }

  shielded_instance_config {
    enable_secure_boot          = var.enable_shielded_vm
    enable_vtpm                 = var.enable_shielded_vm
    enable_integrity_monitoring = var.enable_shielded_vm
  }

  # No service account is attached: this instance gets no GCP API access
  # by default. Add a scoped service_account block if the app needs one.

  allow_stopping_for_update = true
}
