using './main.bicep'

// Required
param storageAccountName = 'sttfstateexample001'
param location           = 'australiaeast'

// Optional – uncomment and set as needed
// param resourceGroupName            = 'rg-tfstate-prd'
// param containerName                = 'tfstate'
// param allowedIpAddressesOrRanges = [
//   '203.0.113.10'
//   '198.51.100.0/24'
// ]
// param blobDataContributorObjectIds = [
//   '00000000-0000-0000-0000-000000000000'
// ]
// param tags = {
//   environment: 'prd'
//   workload:    'terraform-state'
// }
