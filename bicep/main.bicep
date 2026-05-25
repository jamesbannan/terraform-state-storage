targetScope = 'subscription'

metadata name = 'Terraform State Storage – standalone'
metadata description = 'Deploys a WAF-aligned Azure Storage Account suitable as a Terraform remote state backend, with no dependencies on other resources. Composed entirely from Azure Verified Modules.'

// =========================================================================
// Parameters
// =========================================================================

@description('Required. Globally unique name of the Storage Account. 3-24 lowercase alphanumeric characters.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Required. Azure region into which all resources are deployed.')
param location string

@description('Optional. Name of the Resource Group to create. Defaults to "rg-<storageAccountName>".')
param resourceGroupName string = 'rg-${storageAccountName}'

@description('Optional. Name of the blob container that will hold Terraform state files.')
param containerName string = 'tfstate'

@description('Optional. List of public IPv4 addresses or CIDR ranges permitted to access the Storage Account data plane. Leave empty to deny all public IP access (Azure trusted-services bypass remains in effect).')
param allowedIpAddressesOrRanges array = []

@description('Optional. Additional Entra ID object IDs (users, groups, or service principals) to grant the Storage Blob Data Contributor role. The identity running this deployment is granted the role automatically.')
param blobDataContributorObjectIds array = []

@description('Optional. Tags applied to every resource created by this deployment.')
param tags object = {}

// =========================================================================
// Variables
// =========================================================================

var deployerObjectId = deployer().objectId

var blobDataContributorPrincipalIds = union([deployerObjectId], blobDataContributorObjectIds)

var ipRules = [
  for ipOrRange in allowedIpAddressesOrRanges: {
    value: ipOrRange
    action: 'Allow'
  }
]

var roleAssignments = [
  for principalId in blobDataContributorPrincipalIds: {
    principalId: principalId
    roleDefinitionIdOrName: 'Storage Blob Data Contributor'
  }
]

// =========================================================================
// Resources
// =========================================================================

module rg 'br/public:avm/res/resources/resource-group:0.4.0' = {
  name: 'tfstate-rg-${uniqueString(deployment().name, resourceGroupName)}'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module storageAccount 'br/public:avm/res/storage/storage-account:0.32.0' = {
  name: 'tfstate-sa-${uniqueString(deployment().name, storageAccountName)}'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
  params: {
    name: storageAccountName
    location: location
    tags: tags

    kind: 'StorageV2'
    skuName: 'Standard_ZRS'
    accessTier: 'Hot'

    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    publicNetworkAccess: 'Enabled'
    requireInfrastructureEncryption: true

    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: ipRules
      virtualNetworkRules: []
    }

    managedIdentities: {
      systemAssigned: true
    }

    blobServices: {
      isVersioningEnabled: true
      changeFeedEnabled: true
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 7
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 7
      containers: [
        {
          name: containerName
          publicAccess: 'None'
        }
      ]
    }

    roleAssignments: roleAssignments
  }
}

// =========================================================================
// Outputs
// =========================================================================

@description('Name of the Resource Group that contains the Storage Account.')
output resourceGroupName string = resourceGroupName

@description('Resource ID of the Storage Account.')
output storageAccountId string = storageAccount.outputs.resourceId

@description('Name of the Storage Account.')
output storageAccountName string = storageAccount.outputs.name

@description('Name of the blob container that will hold Terraform state files.')
output containerName string = containerName

@description('Values consumable by a Terraform `backend "azurerm"` block.')
output backendConfig object = {
  resource_group_name: resourceGroupName
  storage_account_name: storageAccount.outputs.name
  container_name: containerName
  use_azuread_auth: true
}
