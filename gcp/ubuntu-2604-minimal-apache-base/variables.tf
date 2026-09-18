variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone (must be in region)."
  type        = string
  default     = "us-central1-a"
}

variable "name_prefix" {
  description = "Prefix applied to all resource names/tags created by this template."
  type        = string
  default     = "ubuntu2604-apache"
}

variable "labels" {
  description = "Labels applied to resources that support them."
  type        = map(string)
  default     = {}
}

# --- Networking -------------------------------------------------------------

variable "subnet_cidr" {
  description = "CIDR range for the subnetwork the instance's NIC is attached to."
  type        = string
  default     = "10.61.0.0/26"
}

variable "enable_public_ip" {
  description = <<-EOT
    Whether to assign a static external IP to the instance. Leave this
    false (default) for a fully private instance reached over SSH via a
    jumpbox/VPN/Cloud Interconnect and managed by Ansible over a private
    network. Only enable this for lab/demo scenarios where
    admin_source_cidr_ranges is tightly scoped - the web ports are
    internet-facing by default (web_source_cidr_ranges) once a public IP
    exists.
  EOT
  type        = bool
  default     = false
}

variable "admin_source_cidr_ranges" {
  description = <<-EOT
    CIDR ranges allowed to reach TCP/22 (SSH) on the instance, e.g. your
    Ansible control node(s) or management VPN range. Must be explicitly
    set - there is no default. This template builds a custom-mode VPC,
    which denies all ingress by default, so nothing is reachable unless
    a firewall rule explicitly allows it.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.admin_source_cidr_ranges) > 0
    error_message = "admin_source_cidr_ranges must contain at least one CIDR range; it is not allowed to default open."
  }
}

variable "web_source_cidr_ranges" {
  description = "CIDR ranges allowed to reach TCP/80 and TCP/443 (Apache). Defaults to the internet since this is a web server. Only reachable at all once enable_public_ip is true."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Compute ------------------------------------------------------------

variable "machine_type" {
  description = "GCE machine type. Ignored if both custom_cpu_count and custom_memory_mb are set - those build a custom machine type instead."
  type        = string
  default     = "e2-small"
}

variable "custom_cpu_count" {
  description = <<-EOT
    Number of vCPUs for a custom machine type, dialed independently of
    memory (unlike the fixed vCPU/memory bundles of predefined machine
    types like e2-small). Must be set together with custom_memory_mb;
    when both are set, this overrides machine_type entirely. Must be an
    even number for most families (N-series custom types require even
    counts >= 2).
  EOT
  type        = number
  default     = null
}

variable "custom_memory_mb" {
  description = "Memory in MB for a custom machine type. Must be a multiple of 256 and set together with custom_cpu_count."
  type        = number
  default     = null
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB."
  type        = number
  default     = 20
}

variable "boot_disk_type" {
  description = "Boot disk type."
  type        = string
  default     = "pd-balanced"
}

variable "data_disks" {
  description = <<-EOT
    Additional persistent disks to attach to the instance beyond the boot
    disk. Each is formatted (ext4) and mounted under /mnt/dataN
    automatically by cloud-init - no manual disk management needed in the
    guest. This is for extra local block storage; for existing shared
    network storage (an NFS export, an SMB share, an S3 bucket), use
    additional_mounts instead.
  EOT
  type = list(object({
    size_gb = number
    type    = optional(string, "pd-balanced")
  }))
  default = []
}

variable "additional_mounts" {
  description = <<-EOT
    Existing network storage to mount inside the instance after boot -
    e.g. an NFS export (Filestore, EFS via VPN/interconnect, etc.), an
    SMB/CIFS share (a generic NAS), or an S3(-compatible) bucket (via
    s3fs). This does not create the storage itself, only mounts it - the
    source must already exist.
  EOT
  type = list(object({
    type        = string           # "nfs" | "smb" | "s3"
    source      = string           # e.g. "10.0.0.4:/vol1", "//server/share", "my-bucket"
    mount_point = string           # e.g. "/mnt/data"
    options     = optional(string, "")
  }))
  default = []

  validation {
    condition     = alltrue([for m in var.additional_mounts : contains(["nfs", "smb", "s3"], m.type)])
    error_message = "additional_mounts[*].type must be one of: nfs, smb, s3."
  }
}

variable "image_project" {
  description = "Project publishing the source image."
  type        = string
  default     = "ubuntu-os-cloud"
}

variable "image_family" {
  description = <<-EOT
    Image family for the Ubuntu 26.04 LTS minimal image. Verify this
    matches a published family before applying, e.g.:
      gcloud compute images list --project ubuntu-os-cloud --filter="family~2604" --format="table(name,family)"
    If 26.04 isn't published yet, fall back to "ubuntu-minimal-2404-lts-amd64".
  EOT
  type        = string
  default     = "ubuntu-minimal-2604-lts-amd64"
}

variable "admin_username" {
  description = "SSH username created on the instance via metadata SSH keys."
  type        = string
  default     = "ansible"
}

variable "ssh_public_key" {
  description = "SSH public key (e.g. contents of an id_ed25519.pub) authorized for admin_username. Used by Ansible for management; password auth is disabled."
  type        = string
}

variable "enable_shielded_vm" {
  description = "Enable Shielded VM options (Secure Boot, vTPM, integrity monitoring) - GCP's equivalent of Trusted Launch."
  type        = bool
  default     = true
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
