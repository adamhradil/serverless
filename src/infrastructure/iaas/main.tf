resource "azurerm_virtual_network" "iaas_vnet" {
  name                = "iaas-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "iaas_subnet" {
  name                 = "iaas-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.iaas_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "iaas_ip" {
  name                = "iaas-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "iaas_nsg" {
  name                = "iaas-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_network_security_rule" "ssh" {
  name                        = "SSH"
  priority                    = 1001
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.iaas_nsg.name
}

resource "azurerm_network_interface" "iaas_nic" {
  name                = "iaas-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.iaas_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.iaas_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "iaas_nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.iaas_nic.id
  network_security_group_id = azurerm_network_security_group.iaas_nsg.id
}

resource "tls_private_key" "iaas_ssh" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "iaas_ssh_key" {
  content         = tls_private_key.iaas_ssh.private_key_openssh
  filename        = "${path.module}/iaas_key.pem"
  file_permission = "0600"
}

resource "azurerm_linux_virtual_machine" "iaas_vm" {
  name                = "iaas-benchmark-vm"
  resource_group_name = var.resource_group_name
  location            = var.location
  size           = "Standard_B2ts_v2"
  admin_username = "azureuser"

  network_interface_ids = [
    azurerm_network_interface.iaas_nic.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.iaas_ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  lifecycle {
    ignore_changes = [custom_data]
  }

  custom_data = base64encode(templatefile("${path.module}/setup.yml", {
    SQL_SERVER                            = var.SQL_SERVER
    SQL_USER                              = var.SQL_USER
    SQL_PASSWORD                          = var.SQL_PASSWORD
    SQL_DATABASE                          = var.SQL_DATABASE
    GOLEMIO_API_KEY                       = var.GOLEMIO_API_KEY
    ACR_LOGIN_SERVER                      = var.ACR_LOGIN_SERVER
    ACR_ADMIN_USERNAME                    = var.ACR_ADMIN_USERNAME
    ACR_ADMIN_PASSWORD                    = var.ACR_ADMIN_PASSWORD
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.APPLICATIONINSIGHTS_CONNECTION_STRING
  }))
}
