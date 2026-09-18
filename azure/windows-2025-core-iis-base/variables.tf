variable "name_prefix" {
  description = "Prefix applied to all resource names created by this template."
  type        = string
  default     = "win2025-iis"
}

variable "location" {
  description = "Azure region to deploy into."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group to create for this deployment."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource created by this template."
  type        = map(string)
  default     = {}
}

# --- Networking -------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space for the virtual network created by this template."
  type        = list(string)
  default     = ["10.60.0.0/24"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the subnet the VM's NIC is attached to."
  type        = list(string)
  default     = ["10.60.0.0/26"]
}

variable "enable_public_ip" {
  description = <<-EOT
    Whether to attach a public IP to the VM's NIC. Leave this false (default) for
    a fully private instance managed over SSH via a jumpbox/VPN/Bastion and
    reached by Ansible over a private network. Only enable this for lab/demo
    scenarios where the admin_source_address_prefixes allow-list is tightly scoped.
  EOT
  type        = bool
  default     = false
}

variable "admin_source_address_prefixes" {
  description = <<-EOT
    CIDR blocks allowed to reach TCP/22 (SSH) on the instance, e.g. your Ansible
    control node(s) or management VPN range. Must be explicitly set - there is
    no default - so nobody accidentally opens SSH to the world.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.admin_source_address_prefixes) > 0
    error_message = "admin_source_address_prefixes must contain at least one CIDR block; it is not allowed to default open."
  }
}

variable "web_source_address_prefixes" {
  description = "CIDR blocks allowed to reach TCP/80 and TCP/443 (IIS). Defaults to the internet since this is a web server."
  type        = list(string)
  default     = ["Internet"]
}

# --- Compute ------------------------------------------------------------

variable "vm_size" {
  description = "Azure VM size."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "os_disk_type" {
  description = "Managed disk storage account type for the OS disk."
  type        = string
  default     = "StandardSSD_LRS"
}

variable "image_publisher" {
  description = "Marketplace image publisher."
  type        = string
  default     = "MicrosoftWindowsServer"
}

variable "image_offer" {
  description = "Marketplace image offer."
  type        = string
  default     = "WindowsServer"
}

variable "image_sku" {
  description = <<-EOT
    Marketplace image SKU. Defaults to the Windows Server 2025 Datacenter Core
    Gen2 image. Verify the exact SKU string available in your target region
    before applying, e.g.:
      az vm image list-skus --location <region> \
        --publisher MicrosoftWindowsServer --offer WindowsServer -o table
  EOT
  type        = string
  default     = "2025-datacenter-core-g2"
}

variable "image_version" {
  description = "Marketplace image version."
  type        = string
  default     = "latest"
}

variable "admin_username" {
  description = "Local administrator username created on the VM. This account's authorized_keys is used for SSH access."
  type        = string
  default     = "azadmin"
}

variable "admin_password" {
  description = <<-EOT
    Local administrator password. If left null, a strong random password is
    generated and stored only in Terraform state - protect state accordingly
    (remote state with encryption + access control), or supply your own
    password sourced from a secrets manager (e.g. Azure Key Vault).
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key (e.g. contents of an id_ed25519.pub) authorized for the admin_username account. Used by Ansible for management; password auth is disabled."
  type        = string
}

variable "enable_trusted_launch" {
  description = "Enable Trusted Launch (Secure Boot + vTPM) on the VM. Requires a Gen2 image."
  type        = bool
  default     = true
}

variable "enable_encryption_at_host" {
  description = "Enable encryption at host for the VM's disks. Requires the EncryptionAtHost feature to be registered on the subscription."
  type        = bool
  default     = false
}
