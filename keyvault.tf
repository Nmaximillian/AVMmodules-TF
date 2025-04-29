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

# Get Azure authentication info (subscription_id, tenant_id)
data "azurerm_client_config" "this" {}

provider "azurerm" {
  features {}

  subscription_id = data.azurerm_client_config.this.subscription_id
  tenant_id       = data.azurerm_client_config.this.tenant_id
}

# Get a list of regions
module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.3.0"
}

# Pick a random region (not used here but still initialized)
resource "random_integer" "region_index" {
  max = length(module.regions.regions) - 1
  min = 0
}

# Create a random-compliant resource name helper
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.3.0"
}

# Create Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-avm-test-001"
  location = "westeurope" # or module.regions.regions[random_integer.region_index.result] if you want randomized
}

# Deploy Key Vault using the AVM module pulled from ACR
module "keyvault" {
  source = "./modules/avm-res-keyvault-vault"

  name                = "zstestkv0101001"
  enable_telemetry    = true
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.this.tenant_id
}
