terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "=3.19.1"
            }
        }
    required_version = ">= 0.14.1"
}

variable "subscriptionId" {}
variable "tenantId" {}
variable "clientId" {}
variable "clientSecret" {}
variable "instance_parameters" {
  type = map
  default = {
    "name" = "master"
  }
}

provider "azurerm" {
  #version = "3.22.0"
  subscription_id = var.subscriptionId
  tenant_id = var.tenantId
  client_id = var.clientId
  client_secret = var.clientSecret
  features {}
}

#create resource group
resource "azurerm_resource_group" "dg-rg-1" {
    name = "dg-rg-${var.instance_parameters["name"]}"
    location = "centralus"
}

#create a network
resource "azurerm_virtual_network" "dg-vnet-1" {
    name = "dg-vnet-${var.instance_parameters["name"]}"
    address_space = ["10.10.0.0/16"]
    location = "centralus"
    resource_group_name = azurerm_resource_group.dg-rg-1.name
    tags = {
        environment = "DG Terraform"
    }
}

#create a subnet
resource "azurerm_subnet" "dg-subnet-1" {
    name = "dg-subnet-${var.instance_parameters["name"]}"
    resource_group_name = azurerm_resource_group.dg-rg-1.name
    virtual_network_name = azurerm_virtual_network.dg-vnet-1.name
    address_prefixes = ["10.10.2.0/24"]
}

#create a public ip
resource "azurerm_public_ip" "dg-ip-1" {
    name = "dg-ip-${var.instance_parameters["name"]}"
    location = "centralus"
    resource_group_name = azurerm_resource_group.dg-rg-1.name
    allocation_method = "Dynamic"
    tags = {
        environment = "DG Terraform"
    }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "dg-sg-1" {
    name                = "dg-sg-${var.instance_parameters["name"]}"
    location            = "centralus"
    resource_group_name = azurerm_resource_group.dg-rg-1.name
    security_rule {
        name = "SSH"
        priority = 1001
        direction = "Inbound"
        access = "Allow"
        protocol = "Tcp"
        source_port_range = "*"
        destination_port_range = "22"
        source_address_prefix = "*"
        destination_address_prefix = "*"
    }
    tags = {
        environment = "DG Terraform"
    }
}

# Create network interface
resource "azurerm_network_interface" "dg-nic-1" {
    name = "dg-nic-${var.instance_parameters["name"]}"
    location = "centralus"
    resource_group_name = azurerm_resource_group.dg-rg-1.name
    ip_configuration {
        name = "dg-nic-config-${var.instance_parameters["name"]}"
        subnet_id = azurerm_subnet.dg-subnet-1.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id = azurerm_public_ip.dg-ip-1.id
    }
    tags = {
        environment = "DG Terraform"
    }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "dg-sg-nic-1" {
    network_interface_id = azurerm_network_interface.dg-nic-1.id
    network_security_group_id = azurerm_network_security_group.dg-sg-1.id
}

# Create (and display) an SSH key
resource "tls_private_key" "dg-key-1" {
  algorithm = "RSA"
  rsa_bits = 4096
}
output "tls_private_key" { value = "${tls_private_key.dg-key-1.private_key_pem}" }

# Create virtual machine
resource "azurerm_linux_virtual_machine" "dg-vm-1" {
    name = "dg-vm-${var.instance_parameters["name"]}"
    location = "centralus"
    resource_group_name = azurerm_resource_group.dg-rg-1.name
    network_interface_ids = [azurerm_network_interface.dg-nic-1.id]
    size = "Standard_DS1_v2"
    os_disk {
        name = "dg-vm-os-disk-${var.instance_parameters["name"]}"
        caching = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }
    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04.0-LTS"
        version   = "latest"
    }
    computer_name  = "dg-vm-${var.instance_parameters["name"]}"
    admin_username = "dgaharwar"
    disable_password_authentication = true
    admin_ssh_key {
        username       = "dgaharwar"
        public_key     = tls_private_key.dg-key-1.public_key_openssh
    }
    tags = {
        environment = "DG Terraform"
        applicationRole = "${var.instance_parameters["name"]}-app"
    }
}
