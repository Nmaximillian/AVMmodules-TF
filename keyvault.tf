terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.117"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {}
}

# Get tenant id
data "azurerm_client_config" "this" {}

# Randomized region
module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.3.0"
}

resource "random_integer" "region_index" {
  max = length(module.regions.regions) - 1
  min = 0
}

# Naming
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.3.0"
}

# Resource group
resource "azurerm_resource_group" "rg" {
  name     = "rg-avm-test-001"
  location = "westeurope"
}

# The KeyVault
module "keyvault" {
  source  = "oci://avmmodulestf.azurecr.io/avm-res-keyvault-vault/azurerm"
  version = "0.1.0"

  name                = "zstestkv0101001"
  enable_telemetry    = true
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.this.tenant_id
}
