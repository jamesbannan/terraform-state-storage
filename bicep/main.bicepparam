using './main.bicep'

// Required
param storageAccountName = 'sttfstateexample001'
param location           = 'australiaeast'

// Optional – uncomment and set as needed
// param resourceGroupName            = 'rg-tfstate-prd'
// param containerName                = 'tfstate'
// param allowedIpAddressOrRange      = '203.0.113.10'
// param blobDataContributorObjectIds = [
//   '00000000-0000-0000-0000-000000000000'
// ]
// param tags = {
//   environment: 'prd'
//   workload:    'terraform-state'
// }
