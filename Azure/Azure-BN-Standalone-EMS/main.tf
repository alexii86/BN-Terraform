terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.94.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# First we'll create a resource group. In Azure every resource belongs to a 
# resource group. Think of it as a container to hold all your resources. 
# You can find a complete list of Azure resources supported by Terraform here:
# https://www.terraform.io/docs/providers/azurerm/
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group
  location = var.location
}

resource "azurerm_availability_set" "bn_aset" {
  name                = "bn-aset"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.rg.location
  }

  byte_length = 2
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "mystorageaccount" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create a Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet"
  location            = azurerm_resource_group.rg.location
  address_space       = ["${var.address_space}"]
  resource_group_name = azurerm_resource_group.rg.name
}


resource "azurerm_subnet" "public_subnet" {
  name                 = "BN-Public-Subnet"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_resource_group.rg.name
  address_prefixes     = ["${var.public_prefix}"]
}

resource "azurerm_subnet" "private_subnet" {
  name                 = "BN-Private-Subnet"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_resource_group.rg.name
  address_prefixes     = ["${var.private_prefix}"]
}

resource "azurerm_subnet" "mgmt_subnet" {
  name                 = "BN-MGMT-Subnet"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_resource_group.rg.name
  address_prefixes     = ["${var.mgmt_prefix}"]
}

resource "azurerm_network_security_group" "bn-sg" {
  name                = "bn-sg"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "HTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

 security_rule {
    name                       = "BNEMS-Mgmt"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}


resource "azurerm_network_interface" "bn_mgmt_int" {
  name                = "bn_mgmt_int"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "bn_mgmt_int_ipconfig"
    subnet_id                     = azurerm_subnet.mgmt_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.bn-mgmt-pip.id
  }
}

resource "azurerm_network_interface" "ems_mgmt_int" {
  name                = "ems_mgmt_int"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ems_mgmt_int_ipconfig"
    subnet_id                     = azurerm_subnet.mgmt_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ems-mgmt-pip.id
  }
}

resource "azurerm_network_interface" "bn_public_int" {
  name                = "bn_public_int"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "public_int_ipconfig"
    subnet_id                     = azurerm_subnet.public_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "bn_private_int" {
  name                = "bn_private_int"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "bn_private_int_ipconfig"
    subnet_id                     = azurerm_subnet.private_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "bn_mgmt_sg_assoc" {
  network_interface_id      = azurerm_network_interface.bn_mgmt_int.id
  network_security_group_id = azurerm_network_security_group.bn-sg.id
}

resource "azurerm_network_interface_security_group_association" "ems_mgmt_sg_assoc" {
  network_interface_id      = azurerm_network_interface.ems_mgmt_int.id
  network_security_group_id = azurerm_network_security_group.bn-sg.id
}

resource "azurerm_network_interface_security_group_association" "public_sg_assoc" {
  network_interface_id      = azurerm_network_interface.bn_public_int.id
  network_security_group_id = azurerm_network_security_group.bn-sg.id
}

resource "azurerm_network_interface_security_group_association" "private_sg_assoc" {
  network_interface_id      = azurerm_network_interface.bn_private_int.id
  network_security_group_id = azurerm_network_security_group.bn-sg.id
}



# Every Azure Virtual Machine comes with a private IP address. You can also 
# optionally add a public IP address for Internet-facing applications 
resource "azurerm_public_ip" "bn-mgmt-pip" {
  name                = "bn-mgmt-ip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_public_ip" "ems-mgmt-pip" {
  name                = "ems-mgmt-ip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_image" "bn_image" {
  name                = "bn_image"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  os_disk {
    os_type  = "Linux"
    os_state = "Generalized"
    blob_uri = var.bn_os_disk
  }
  data_disk {
    lun      = "0"
    blob_uri = var.bn_data_disk
  }
}

resource "azurerm_image" "ems_image" {
  name                = "ems_image"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  os_disk {
    os_type  = "Linux"
    os_state = "Generalized"
    blob_uri = var.ems_os_disk
  }
  data_disk {
    lun      = "0"
    blob_uri = var.ems_data_disk
  }
}

resource "azurerm_virtual_machine" "bn1" {
  name                = "Enghouse-BorderNet-SBC"
  location            = var.location
  availability_set_id = azurerm_availability_set.bn_aset.id
  resource_group_name = azurerm_resource_group.rg.name
  vm_size             = var.vm_size

  network_interface_ids         = ["${azurerm_network_interface.bn_mgmt_int.id}", "${azurerm_network_interface.bn_public_int.id}", "${azurerm_network_interface.bn_private_int.id}"]
  primary_network_interface_id  = azurerm_network_interface.bn_mgmt_int.id
  delete_os_disk_on_termination = "true"

  storage_image_reference {
    id = azurerm_image.bn_image.id
  }

  storage_os_disk {
    name              = "bn-osdisk"
    managed_disk_type = "StandardSSD_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = "bn1"
    admin_username = "sysadmin"
    admin_password = "Dia10gic"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  boot_diagnostics {
    enabled     = "true"
    storage_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
  }
}

resource "azurerm_virtual_machine" "ems" {
  name                = "Enghouse-BorderNet-EMS"
  location            = var.location
  availability_set_id = azurerm_availability_set.bn_aset.id
  resource_group_name = azurerm_resource_group.rg.name
  vm_size             = var.vm_size

  network_interface_ids         = [azurerm_network_interface.ems_mgmt_int.id]
  delete_os_disk_on_termination = "true"

  storage_image_reference {
    id = azurerm_image.ems_image.id
  }

  storage_os_disk {
    name              = "ems-osdisk"
    managed_disk_type = "StandardSSD_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = "ems"
    admin_username = "sysadmin"
    admin_password = "Dia10gic"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  boot_diagnostics {
    enabled     = "true"
    storage_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
  }
}

output "BN_MGMT_url" {
  value = "https://${azurerm_public_ip.bn-mgmt-pip.ip_address}/"
}

output "EMS_MGMT_url" {
  value = "https://${azurerm_public_ip.ems-mgmt-pip.ip_address}:8443"
}

output "Public_ip_address" {
  value = azurerm_network_interface.bn_public_int.private_ip_address
}

output "Private_ip_address" {
  value = azurerm_network_interface.bn_private_int.private_ip_address
}
