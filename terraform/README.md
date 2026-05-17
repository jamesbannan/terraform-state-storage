# Terraform — Terraform State Storage

Deploys a standalone, WAF-aligned Azure Storage Account intended for use as a Terraform remote state backend. The configuration composes the following Azure Verified Modules:

| Resource | Module | Version |
|---|---|---|
| Resource Group | [`Azure/avm-res-resources-resourcegroup/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm) | `0.2.1` |
| Storage Account (+ blob services, container, RBAC) | [`Azure/avm-res-storage-storageaccount/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm) | `0.6.4` |

The configuration creates its own resource group, so it has no dependencies on pre-existing resources.

> ℹ️ This Terraform configuration is functionally equivalent to the Bicep solution in [`../bicep/`](../bicep/). Either implementation produces the same WAF-aligned backend.

---

## What gets deployed

- A resource group (default name: `rg-<storage_account_name>`).
- A `StorageV2`, `Standard_ZRS`, `Hot`-tier storage account with:
  - TLS 1.2 minimum, HTTPS-only traffic.
  - Shared-key access **disabled** (Entra ID / RBAC only).
  - Public blob access **disabled**, cross-tenant replication **disabled**.
  - Infrastructure encryption **enabled**.
  - `public_network_access_enabled = true` with `network_rules.default_action = "Deny"` and `bypass = ["AzureServices"]`. An optional single IP or CIDR can be allow-listed.
  - System-assigned managed identity.
  - Blob versioning, change feed, and 7-day soft delete (blob + container).
  - A private container named `tfstate` (configurable).
- `Storage Blob Data Contributor` role assignments for:
  - The identity running Terraform (resolved automatically via `azurerm_client_config`).
  - Any additional object IDs you supply.

---

## Prerequisites

- **Terraform** `>= 1.9` — <https://developer.hashicorp.com/terraform/install>
- **Azure CLI** `>= 2.60` (used for `az login` and for the `azurerm` provider's default authentication) — <https://learn.microsoft.com/cli/azure/install-azure-cli>
- Logged in to the target tenant: `az login`
- Permissions on the target **subscription**:
  - `Contributor` (or equivalent) to create the resource group and storage account.
  - `User Access Administrator` (or `Role Based Access Control Administrator`) to create the `Storage Blob Data Contributor` role assignments.
- A globally unique storage account name (3–24 lowercase alphanumeric characters).

---

## Inputs

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `storage_account_name` | `string` | ✅ | — | Globally unique name. 3–24 lowercase alphanumeric chars. |
| `location` | `string` | ✅ | — | Azure region (e.g., `australiaeast`). |
| `subscription_id` | `string` | ⛔ | `null` | Target subscription ID. When `null`, the value is taken from `ARM_SUBSCRIPTION_ID` or the current `az` context. |
| `resource_group_name` | `string` | ⛔ | `rg-<storage_account_name>` | Name of the resource group to create. |
| `container_name` | `string` | ⛔ | `tfstate` | Name of the blob container that holds state files. |
| `allowed_ip_address_or_range` | `string` | ⛔ | `""` | Single public IPv4 address or CIDR allowed through the firewall. Empty = no public IP allowed (Azure trusted-services bypass still applies). |
| `blob_data_contributor_object_ids` | `list(string)` | ⛔ | `[]` | Additional Entra ID object IDs (users, groups, SPs) granted `Storage Blob Data Contributor`. The identity running Terraform is added automatically. |
| `tags` | `map(string)` | ⛔ | `{}` | Tags applied to every resource. |

## Outputs

| Name | Description |
|---|---|
| `resource_group_name` | Name of the resource group that contains the Storage Account. |
| `storage_account_id` | Resource ID of the Storage Account. |
| `storage_account_name` | Name of the Storage Account. |
| `container_name` | Name of the blob container. |
| `backend_config` | Object with `resource_group_name`, `storage_account_name`, `container_name`, `use_azuread_auth = true` — ready to drop into a Terraform `backend "azurerm"` block. |

---

## Step-by-step deployment

### 1. Clone the repository

```bash
git clone https://github.com/jamesbannan/terraform-state-storage.git
cd terraform-state-storage/terraform
```

### 2. Sign in to Azure and select the target subscription

```bash
az login
az account set --subscription "<subscription-id-or-name>"
az account show --output table
```

Optionally export the subscription so Terraform picks it up implicitly:

```bash
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

### 3. Create a `terraform.tfvars` file

```hcl
storage_account_name = "sttfstateprd001"
location             = "australiaeast"

# Optional
# allowed_ip_address_or_range      = "203.0.113.10"
# blob_data_contributor_object_ids = [
#   "00000000-0000-0000-0000-000000000000",
# ]
# tags = {
#   environment = "prd"
#   workload    = "terraform-state"
# }
```

> 💡 Find your current public IP for `allowed_ip_address_or_range`: `curl -4 ifconfig.me`
>
> 💡 Find an Entra object ID: `az ad signed-in-user show --query id -o tsv` (current user) or `az ad sp show --id <appId> --query id -o tsv` (service principal).

> ⚠️ Do **not** commit `terraform.tfvars` if it contains environment-specific values. The repository's `.gitignore` already excludes `*.tfvars`.

### 4. Initialise the working directory

```bash
terraform init
```

This downloads the pinned Azure Verified Modules and the required providers (`azurerm`, `azapi`, `random`, `modtm`).

### 5. Validate and format

```bash
terraform fmt -recursive
terraform validate
```

### 6. Preview the plan

```bash
terraform plan -out tfplan
```

You should see **8 resources to add** (resource group + storage account composite resources) and the planned output values.

### 7. Apply

```bash
terraform apply tfplan
```

The apply typically completes in 1–3 minutes.

### 8. Capture the outputs

```bash
terraform output
terraform output -json backend_config
```

### 9. Use it as a Terraform backend

Add the following to your consuming Terraform configuration, substituting the values from `backend_config`:

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

Re-run `terraform plan` and `terraform apply` after changing any variable. To rotate or add Entra principals on the container, just update `blob_data_contributor_object_ids` and re-apply.

## Deleting the deployment

```bash
terraform destroy
```

> ⚠️ This permanently deletes the storage account and all Terraform state files inside it. Make sure state is migrated or no longer needed first.

> ⚠️ **Do not store this configuration's own state in the storage account it creates.** Bootstrap it with a local backend, then optionally migrate its state into the account afterwards.

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `StorageAccountAlreadyTaken` | `storage_account_name` must be globally unique across Azure. Choose a different name. |
| `AuthorizationFailed` on role assignment | Your principal lacks `User Access Administrator` / `Role Based Access Control Administrator` on the subscription. |
| `403` when running `terraform init` against the new backend | Either the role assignment hasn't propagated yet (wait 1–2 minutes), your client IP isn't in `allowed_ip_address_or_range`, or you forgot `use_azuread_auth = true`. |
| `PublicAccessNotPermitted` from a CI runner | Add the runner's egress IP to `allowed_ip_address_or_range` and re-apply. |
| `Error: building AzureRM Client: please ensure subscription_id is set` | Either set `subscription_id` in `terraform.tfvars` or export `ARM_SUBSCRIPTION_ID`. |
| `Error retrieving Storage Account ... AuthorizationPermissionMismatch` during apply | The provider needs `storage_use_azuread = true` (already set in `providers.tf`) **and** your principal needs Storage Blob Data Contributor or Owner. The deployment grants this to the deployer automatically; if Terraform fails immediately after creating the account, re-run `terraform apply` to let RBAC propagate. |
