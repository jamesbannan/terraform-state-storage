variable "subscription_id" {
  description = "Optional. Azure subscription ID. When null, the value is taken from ARM_SUBSCRIPTION_ID or the current `az` context."
  type        = string
  default     = null
}

variable "storage_account_name" {
  description = "Required. Globally unique name of the Storage Account. 3-24 lowercase alphanumeric characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "location" {
  description = "Required. Azure region into which all resources are deployed."
  type        = string
}

variable "resource_group_name" {
  description = "Optional. Name of the resource group to create. Defaults to \"rg-<storage_account_name>\"."
  type        = string
  default     = null
}

variable "container_name" {
  description = "Optional. Name of the blob container that will hold Terraform state files."
  type        = string
  default     = "tfstate"
}

variable "allowed_ip_addresses_or_ranges" {
  description = "Optional. List of public IPv4 addresses or CIDR ranges permitted to access the Storage Account data plane. Empty list denies all public IP access (Azure trusted-services bypass still applies)."
  type        = list(string)
  default     = []
}

variable "blob_data_contributor_object_ids" {
  description = "Optional. Additional Entra ID object IDs (users, groups, or service principals) to grant the Storage Blob Data Contributor role. The identity running this deployment is granted the role automatically."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Optional. Tags applied to every resource created by this deployment."
  type        = map(string)
  default     = {}
}
