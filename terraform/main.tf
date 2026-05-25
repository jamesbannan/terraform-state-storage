data "azurerm_client_config" "current" {}

locals {
  resource_group_name = coalesce(var.resource_group_name, "rg-${var.storage_account_name}")

  deployer_object_id = data.azurerm_client_config.current.object_id

  blob_data_contributor_principal_ids = distinct(concat(
    [local.deployer_object_id],
    var.blob_data_contributor_object_ids,
  ))

  ip_rules = toset(var.allowed_ip_addresses_or_ranges)

  role_assignments = {
    for principal_id in local.blob_data_contributor_principal_ids :
    "blob-data-contributor-${principal_id}" => {
      role_definition_id_or_name = "Storage Blob Data Contributor"
      principal_id               = principal_id
    }
  }
}

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = local.resource_group_name
  location         = var.location
  tags             = var.tags
  enable_telemetry = false
}

module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.7.0"

  name      = var.storage_account_name
  parent_id = module.resource_group.resource_id
  location  = var.location
  tags      = var.tags

  account_kind                      = "StorageV2"
  account_sku_name                  = "Standard_ZRS"
  access_tier                       = "Hot"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  public_network_access_enabled     = true
  infrastructure_encryption_enabled = true

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = local.ip_rules
  }

  managed_identities = {
    system_assigned = true
  }

  containers = {
    tfstate = {
      name          = var.container_name
      public_access = "None"
    }
  }

  role_assignments = local.role_assignments
  enable_telemetry = false
}

# Blob service properties (versioning, change feed, soft delete) are no longer
# exposed by the AVM storage module v0.7.0. Configure directly via azapi.
# Use azapi_update_resource because Azure auto-creates blobServices/default.
resource "azapi_update_resource" "blob_service" {
  type      = "Microsoft.Storage/storageAccounts/blobServices@2024-01-01"
  name      = "default"
  parent_id = module.storage_account.resource_id

  body = {
    properties = {
      isVersioningEnabled = true
      changeFeed = {
        enabled = true
      }
      deleteRetentionPolicy = {
        enabled = true
        days    = 7
      }
      containerDeleteRetentionPolicy = {
        enabled = true
        days    = 7
      }
    }
  }
}
