# Bicep — Terraform State Storage

Deploys a standalone, WAF-aligned Azure Storage Account intended for use as a Terraform remote state backend. The deployment composes the following Azure Verified Modules:

| Resource | Module | Version |
|---|---|---|
| Resource Group | `br/public:avm/res/resources/resource-group` | `0.4.0` |
| Storage Account (+ blob services, container, RBAC) | `br/public:avm/res/storage/storage-account` | `0.14.3` |

The deployment is **subscription-scoped** and creates its own resource group, so it has no dependencies on pre-existing resources.

---

## What gets deployed

- A resource group (default name: `rg-<storageAccountName>`).
- A `StorageV2`, `Standard_ZRS`, `Hot`-tier storage account with:
  - TLS 1.2 minimum, HTTPS-only traffic.
  - Shared-key access **disabled** (Entra ID / RBAC only).
  - Public blob access **disabled**, cross-tenant replication **disabled**.
  - Infrastructure encryption **enabled**.
  - `publicNetworkAccess = Enabled` with `networkAcls.defaultAction = Deny` and `bypass = AzureServices`. An optional list of IPs/CIDRs can be allow-listed.
  - System-assigned managed identity.
  - Blob versioning, change feed, and 7-day soft delete (blob + container).
  - A private container named `tfstate` (configurable).
- `Storage Blob Data Contributor` role assignments for:
  - The identity running the deployment (resolved automatically via `deployer()`).
  - Any additional object IDs you supply.

---

## Prerequisites

- **Azure CLI** `>= 2.60` — <https://learn.microsoft.com/cli/azure/install-azure-cli>
- **Bicep CLI** `>= 0.30` (bundled with Azure CLI; verify with `az bicep version`)
- Logged in to the target tenant: `az login`
- Permissions on the target **subscription**:
  - `Contributor` (or equivalent) to create the resource group and storage account.
  - `User Access Administrator` (or `Role Based Access Control Administrator`) to create the `Storage Blob Data Contributor` role assignments.
- A globally unique storage account name (3–24 lowercase alphanumeric characters).

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `storageAccountName` | `string` | ✅ | — | Globally unique name. 3–24 lowercase alphanumeric chars. |
| `location` | `string` | ✅ | — | Azure region (e.g., `australiaeast`). |
| `resourceGroupName` | `string` | ⛔ | `rg-<storageAccountName>` | Name of the resource group to create. |
| `containerName` | `string` | ⛔ | `tfstate` | Name of the blob container that holds state files. |
| `allowedIpAddressesOrRanges` | `array` | ⛔ | `[]` | Public IPv4 addresses or CIDR ranges allowed through the firewall. Empty = no public IP allowed (Azure trusted-services bypass still applies). |
| `blobDataContributorObjectIds` | `array` | ⛔ | `[]` | Additional Entra ID object IDs (users, groups, SPs) granted `Storage Blob Data Contributor`. The deployer is added automatically. |
| `tags` | `object` | ⛔ | `{}` | Tags applied to every resource. |

---

## Step-by-step deployment

### 1. Clone the repository

```bash
git clone https://github.com/jamesbannan/terraform-state-storage.git
cd terraform-state-storage/bicep
```

### 2. Sign in to Azure and select the target subscription

```bash
az login
az account set --subscription "<subscription-id-or-name>"
az account show --output table
```

### 3. Edit `main.bicepparam`

Open `main.bicepparam` and set at least `storageAccountName` and `location`. Uncomment and set the optional parameters as needed.

```bicep
using './main.bicep'

param storageAccountName = 'sttfstateprd001'
param location           = 'australiaeast'

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
```

> 💡 To find your current public IP for `allowedIpAddressesOrRanges`: `curl -4 ifconfig.me`
>
> 💡 To find an Entra object ID: `az ad signed-in-user show --query id -o tsv` (current user) or `az ad sp show --id <appId> --query id -o tsv` (service principal).

### 4. Validate locally

```bash
az bicep build --file main.bicep
```

A successful build prints nothing and exits `0`. Remove the generated `main.json` if you don't want to keep it: `rm main.json`.

### 5. Preview the deployment (what-if)

```bash
az deployment sub what-if \
  --name tfstate-bootstrap \
  --location <region> \
  --template-file main.bicep \
  --parameters main.bicepparam
```

Review the resources that will be created. The `<region>` here is the region for the **deployment metadata**; it can be the same as `location` in the parameter file.

### 6. Deploy

```bash
az deployment sub create \
  --name tfstate-bootstrap \
  --location <region> \
  --template-file main.bicep \
  --parameters main.bicepparam
```

The deployment typically completes in 1–3 minutes.

### 7. Capture the outputs

```bash
az deployment sub show \
  --name tfstate-bootstrap \
  --query properties.outputs \
  --output json
```

You should see `resourceGroupName`, `storageAccountId`, `storageAccountName`, `containerName`, and a `backendConfig` object.

### 8. Use it as a Terraform backend

Add the following to your consuming Terraform configuration, substituting the values from `backendConfig`:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-sttfstateprd001"
    storage_account_name = "sttfstateprd001"
    container_name       = "tfstate"
    key                  = "<workload>.tfstate"
    use_azuread_auth     = true
  }
}
```

Then run `terraform init` from your consuming repo. Because shared-key access is disabled, you must authenticate to Azure (via `az login`, a managed identity, or OIDC) before running Terraform.

---

## Updating the deployment

Re-running `az deployment sub create` with the same `--name` performs an incremental update. To change role assignments, just edit `blobDataContributorObjectIds` and redeploy.

## Deleting the deployment

```bash
az group delete --name <resourceGroupName> --yes
```

> ⚠️ This permanently deletes the storage account and all Terraform state files inside it. Make sure state is migrated or no longer needed first.

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `StorageAccountAlreadyTaken` | `storageAccountName` must be globally unique across Azure. Choose a different name. |
| `AuthorizationFailed` on role assignment | Your principal lacks `User Access Administrator` / `Role Based Access Control Administrator` on the subscription. |
| `403` when running `terraform init` against the new backend | Either the role assignment hasn't propagated yet (wait 1–2 minutes), your client IP isn't in `allowedIpAddressesOrRanges`, or you forgot `use_azuread_auth = true`. |
| `PublicAccessNotPermitted` from a CI runner | Add the runner's egress IP to `allowedIpAddressesOrRanges` and redeploy. |
| Bicep can't resolve AVM module versions | Run `az bicep install --version latest` and confirm internet access to `mcr.microsoft.com`. |
