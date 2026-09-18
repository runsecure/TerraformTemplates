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
    Name of an existing Ubuntu 26.04 minimal template already present in
    vCenter, with cloud-init >= 21.3 installed and the VMware guestinfo
    datasource available (Canonical's official Ubuntu OVA cloud images
    ship this already). The template must have had `cloud-init clean`
    run before being converted to a template/shut down, or cloud-init
    won't recognize this clone as a new instance and will skip
    provisioning. Unlike the cloud templates in this repo, there is no
    marketplace image lookup here - you must have already built this
    golden image yourself.
  EOT
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to the VM's name."
  type        = string
  default     = "ubuntu2604-apache"
}

variable "num_cpus" {
  description = "Number of vCPUs."
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Memory in MB."
  type        = number
  default     = 2048
}

variable "disk_size_gb" {
  description = "Disk size in GB for the primary disk. If null, inherits the template's own disk size."
  type        = number
  default     = null
}

variable "admin_username" {
  description = "SSH username created on the VM via cloud-init."
  type        = string
  default     = "ansible"
}

variable "ssh_public_key" {
  description = "SSH public key (e.g. contents of an id_ed25519.pub) authorized for admin_username. Used by Ansible for management; password auth is disabled."
  type        = string
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

# --- Networking (guest OS IP config - not a security boundary) -------------

variable "ipv4_address" {
  description = "Static IPv4 address for the VM's NIC. Leave null for DHCP (the template's netplan default)."
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

variable "dns_servers" {
  description = "DNS servers, used only when ipv4_address is set (static network-config)."
  type        = list(string)
  default     = []
}

variable "network_interface_name" {
  description = <<-EOT
    Guest interface name to configure when ipv4_address is set (cloud-init
    network-config v2 needs an explicit interface match). VMware VMs with
    a vmxnet3 adapter commonly show up as "ens192", but this varies by
    template/OS - verify against your golden image with
    `ip -br link` before relying on a static IP.
  EOT
  type        = string
  default     = "ens192"
}
