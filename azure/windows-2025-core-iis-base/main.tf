resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.name_prefix}-rg")
  admin_password      = coalesce(var.admin_password, try(random_password.admin[0].result, null))

  bootstrap_script = templatefile("${path.module}/scripts/bootstrap.ps1.tftpl", {
    ssh_public_key         = var.ssh_public_key
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

  # No RDP (3389) or WinRM (5985/5986) rules are defined anywhere in this
  # template - management is via SSH only, for Ansible.

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

resource "azurerm_windows_virtual_machine" "this" {
  name = "${var.name_prefix}-vm-${random_id.suffix.hex}"
  # Windows computer names are capped at 15 characters; name_prefix can be
  # arbitrarily long, so derive a short, guaranteed-unique hostname instead
  # of relying on this resource's `name`.
  computer_name        = "vm-${random_id.suffix.hex}"
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  size                 = var.vm_size
  admin_username       = var.admin_username
  admin_password       = local.admin_password
  network_interface_ids = [
    azurerm_network_interface.this.id,
  ]
  tags = var.tags

  # Core edition: no Windows GUI/desktop experience installed.
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

  boot_diagnostics {}
}

# Additional data disks - initialized, brought online, and formatted by
# the bootstrap script (see scripts/bootstrap.ps1.tftpl).
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
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  lun                = count.index
  caching            = "ReadWrite"
}

resource "azurerm_virtual_machine_extension" "bootstrap" {
  name                       = "bootstrap-iis-ssh-hardening"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = "powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(local.bootstrap_script, "UTF-16LE")}"
  })

  tags = var.tags

  # Data disks must be attached before the bootstrap script runs, since it
  # initializes/formats any raw disks it finds.
  depends_on = [azurerm_virtual_machine_data_disk_attachment.data]
}
