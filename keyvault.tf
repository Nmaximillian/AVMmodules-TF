provider "azurerm" {
  features {}
}

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
    module_registry {
    "avmmodulestf.azurecr.io" = {
      type = "oci"
      }
    }
  }
}

# We need the tenant id for the key vault.
data "azurerm_client_config" "this" {}

# This allows us to randomize the region for the resource group.
module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.3.0"
}

# This allows us to randomize the region for the resource group.
resource "random_integer" "region_index" {
  max = length(module.regions.regions) - 1
  min = 0
}

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.3.0"
}

# This is required for resource modules
resource "azurerm_resource_group" "rg" {
  name     = "rg-avm-test-001"
  location = "westeurope" # Change to your preferred region
}

# This is the module call
module "keyvault" {
  source  = "oci://avmmodulestf.azurecr.io/avm-res-keyvault-vault/azurerm"
  version = "0.1.0"
  name                = "zstestkv0101001"
  enable_telemetry    = true
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.this.tenant_id
}