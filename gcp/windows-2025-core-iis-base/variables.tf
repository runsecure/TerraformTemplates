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
  default     = "win2025-iis"
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
  default     = "10.60.0.0/26"
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
  description = "CIDR ranges allowed to reach TCP/80 and TCP/443 (IIS). Defaults to the internet since this is a web server. Only reachable at all once enable_public_ip is true."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Compute ------------------------------------------------------------

variable "machine_type" {
  description = "GCE machine type. Ignored if both custom_cpu_count and custom_memory_mb are set - those build a custom machine type instead."
  type        = string
  default     = "e2-medium"
}

variable "custom_cpu_count" {
  description = <<-EOT
    Number of vCPUs for a custom machine type, dialed independently of
    memory (unlike the fixed vCPU/memory bundles of predefined machine
    types like e2-medium). Must be set together with custom_memory_mb;
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
  default     = 50
}

variable "boot_disk_type" {
  description = "Boot disk type."
  type        = string
  default     = "pd-balanced"
}

variable "data_disks" {
  description = <<-EOT
    Additional persistent disks to attach to the instance beyond the boot
    disk. Each is initialized, brought online, and formatted (NTFS)
    automatically by the bootstrap script - no manual disk management
    needed in the guest. This is for extra local block storage; for
    existing shared network storage (an NFS export, an SMB share, an S3
    bucket), use additional_mounts instead.
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
    SMB/CIFS share (a generic NAS), or an S3(-compatible) bucket. This
    does not create the storage itself, only mounts it - the source must
    already exist. S3 has no native Windows mount path; entries of type
    "s3" are skipped with a warning - use rclone or a cloud SDK instead.
  EOT
  type = list(object({
    type        = string           # "nfs" | "smb" | "s3"
    source      = string           # e.g. "10.0.0.4:/export" or "\\\\server\\share"
    mount_point = string           # drive letter, e.g. "Z:"
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
  default     = "windows-cloud"
}

variable "image_family" {
  description = <<-EOT
    Image family for the Windows Server 2025 Core image. Verify this
    matches a published family before applying, e.g.:
      gcloud compute images list --project windows-cloud --filter="family~2025" --format="table(name,family)"
  EOT
  type        = string
  default     = "windows-2025-core"
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
    only in Terraform state - protect state accordingly (remote state
    with encryption + access control), or supply your own password
    sourced from a secrets manager (e.g. Secret Manager). Day-to-day
    access is via SSH key, not this password; it exists for break-glass
    console access.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key (e.g. contents of an id_ed25519.pub) authorized for the admin_username account. Used by Ansible for management; password auth over SSH is disabled."
  type        = string
}

variable "enable_shielded_vm" {
  description = "Enable Shielded VM options (Secure Boot, vTPM, integrity monitoring) - GCP's equivalent of Trusted Launch."
  type        = bool
  default     = true
}
