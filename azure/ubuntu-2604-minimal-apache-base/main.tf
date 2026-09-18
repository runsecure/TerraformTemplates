resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.name_prefix}-rg")

  cloud_init = templatefile("${path.module}/scripts/cloud-init.yaml.tftpl", {
    enable_fail2ban            = var.enable_fail2ban
    enable_unattended_upgrades = var.enable_unattended_upgrades
    additional_mounts          = var.additional_mounts
  })
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# --- Networking -------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  name                 = "${var.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.subnet_address_prefixes
}

resource "azurerm_network_security_group" "this" {
  name                = "${var.name_prefix}-nsg"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags

  security_rule {
    name                       = "AllowSSHFromAdmin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.admin_source_address_prefixes
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowWebInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefixes    = var.web_source_address_prefixes
    destination_address_prefix = "*"
  }

  # Explicit deny for clarity/defense-in-depth, in addition to the platform's
  # implicit default-deny rule at priority 65500.
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_public_ip" "this" {
  count = var.enable_public_ip ? 1 : 0

  name                = "${var.name_prefix}-pip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "this" {
  name                = "${var.name_prefix}-nic"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ip ? azurerm_public_ip.this[0].id : null
  }
}

# --- Compute ------------------------------------------------------------

resource "azurerm_linux_virtual_machine" "this" {
  name                = "${var.name_prefix}-vm-${random_id.suffix.hex}"
  computer_name       = "vm-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.this.id,
  ]
  tags = var.tags

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  secure_boot_enabled        = var.enable_trusted_launch
  vtpm_enabled               = var.enable_trusted_launch
  encryption_at_host_enabled = var.enable_encryption_at_host

  patch_mode = "AutomaticByPlatform"

  custom_data = base64encode(local.cloud_init)

  boot_diagnostics {}
}

# Additional data disks - formatted (ext4) and mounted under /mnt/dataN by
# cloud-init (see scripts/cloud-init.yaml.tftpl).
resource "azurerm_managed_disk" "data" {
  count = length(var.data_disks)

  name                 = "${var.name_prefix}-data-${count.index}"
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  storage_account_type = var.data_disks[count.index].type
  create_option        = "Empty"
  disk_size_gb         = var.data_disks[count.index].size_gb
  tags                 = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  count = length(var.data_disks)

  managed_disk_id    = azurerm_managed_disk.data[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.this.id
  lun                = count.index
  caching            = "ReadWrite"
}
