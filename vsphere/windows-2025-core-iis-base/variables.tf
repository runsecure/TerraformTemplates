variable "vsphere_allow_unverified_ssl" {
  description = "Skip vCenter TLS certificate verification. Common in labs with self-signed certs, but leave false and install a proper cert where you can."
  type        = bool
  default     = false
}

variable "datacenter" {
  description = "vSphere datacenter name."
  type        = string
}

variable "cluster" {
  description = "vSphere compute cluster name to place the VM in."
  type        = string
}

variable "datastore" {
  description = "Datastore name to place the VM's disks on."
  type        = string
}

variable "network" {
  description = "Port group / network name for the VM's NIC. Network-layer segmentation (VLANs, NSX-T, physical firewall rules) is the operator's responsibility on-prem - this template does not manage it."
  type        = string
}

variable "folder" {
  description = "VM folder path to place the VM in (e.g. \"web/prod\"). Null places it at the datacenter root."
  type        = string
  default     = null
}

variable "template_name" {
  description = <<-EOT
    Name of an existing Windows Server 2025 Core template already present
    in vCenter, sysprepped and ready for guest customization (VMware Tools
    installed, sysprep files present). Unlike the cloud templates in this
    repo, there is no marketplace image lookup here - you must have
    already built this golden image yourself.
  EOT
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to the VM's name."
  type        = string
  default     = "win2025-iis"
}

variable "num_cpus" {
  description = "Number of vCPUs."
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Memory in MB."
  type        = number
  default     = 8192
}

variable "disk_size_gb" {
  description = "Disk size in GB for the primary disk. If null, inherits the template's own disk size."
  type        = number
  default     = null
}

variable "admin_username" {
  description = "Local administrator username on the VM. This account's authorized_keys is used for SSH access."
  type        = string
  default     = "Administrator"
}

variable "admin_password" {
  description = <<-EOT
    Local administrator password, applied via vSphere guest customization
    during clone. If left null, a strong random password is generated and
    stored only in Terraform state - protect state accordingly. Day-to-day
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

variable "windows_time_zone" {
  description = <<-EOT
    Numeric Windows sysprep time zone index (VMware's
    CustomizationWinOptions.timeZone field uses the legacy Microsoft time
    zone index, not the modern IANA/Windows time zone name string).
    Defaults to 035 (Pacific Standard Time) - verify against Microsoft's
    historical "time zone index values" reference and adjust for your
    environment.
  EOT
  type        = number
  default     = 35
}

# --- Networking (guest OS IP config - not a security boundary) -------------

variable "ipv4_address" {
  description = "Static IPv4 address for the VM's NIC. Leave null for DHCP."
  type        = string
  default     = null
}

variable "ipv4_prefix_length" {
  description = "Prefix length (e.g. 24) for ipv4_address. Required if ipv4_address is set."
  type        = number
  default     = null
}

variable "ipv4_gateway" {
  description = "IPv4 gateway. Required if ipv4_address is set."
  type        = string
  default     = null
}

variable "dns_server_list" {
  description = "DNS servers for the VM. Leave empty to use whatever DHCP/the template provides."
  type        = list(string)
  default     = []
}
