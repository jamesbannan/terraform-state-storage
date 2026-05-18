output "resource_group_name" {
  description = "Name of the Resource Group that contains the Storage Account."
  value       = module.resource_group.name
}

output "storage_account_id" {
  description = "Resource ID of the Storage Account."
  value       = module.storage_account.resource_id
}

output "storage_account_name" {
  description = "Name of the Storage Account."
  value       = module.storage_account.name
}

output "container_name" {
  description = "Name of the blob container that will hold Terraform state files."
  value       = var.container_name
}

output "backend_config" {
  description = "Values consumable by a Terraform `backend \"azurerm\"` block."
  value = {
    resource_group_name  = module.resource_group.name
    storage_account_name = module.storage_account.name
    container_name       = var.container_name
    use_azuread_auth     = true
  }
}
