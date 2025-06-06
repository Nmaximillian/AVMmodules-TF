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
  subscription_id = "11bfbc32-fbf7-49ab-b0f4-6901dbb6c30b"
}

data "azurerm_client_config" "this" {}

module "regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.3.0"
}

resource "random_integer" "region_index" {
  max = length(module.regions.regions) - 1
  min = 0
}

module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.3.0"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-avmtf-test-001"
  location = "westeurope"
}

module "keyvault" {
  source = "./modules/avm-res-keyvault-vault"

  name                = "zstestkv0002"
  enable_telemetry    = true
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.this.tenant_id
}
