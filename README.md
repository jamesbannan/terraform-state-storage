# Terraform State Storage

Bootstraps a **WAF-aligned Azure Storage Account** for use as a [Terraform remote state backend](https://developer.hashicorp.com/terraform/language/backend/azurerm), deployed entirely via [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/).

Two parallel IaC implementations are provided — choose whichever fits your toolchain:

| Implementation | Path | Modules |
|---|---|---|
| **Terraform** | [`terraform/`](./terraform/) | `avm-res-resources-resourcegroup` `0.4.0`, `avm-res-storage-storageaccount` `0.7.0` |
| **Bicep** | [`bicep/`](./bicep/) | `avm/res/resources/resource-group` `0.4.0`, `avm/res/storage/storage-account` `0.32.0` |

Both produce a functionally equivalent deployment.

---

## What gets deployed

- A **resource group** (default: `rg-<storage_account_name>`)
- A **StorageV2 / Standard_ZRS / Hot** storage account with:
  - Shared-key access **disabled** — Entra ID (RBAC) only
  - Public blob access **disabled**, cross-tenant replication **disabled**
  - TLS 1.2 minimum, HTTPS-only
  - Infrastructure encryption **enabled**
  - Network rules: default **Deny** with Azure Services bypass; optional IP allow-list
  - System-assigned managed identity
  - Blob versioning, change feed, 7-day soft delete (blobs + containers)
- A private blob container (`tfstate` by default)
- **Storage Blob Data Contributor** role assignments for the deploying principal and any additional object IDs

---

## Quick start

### Bicep (recommended for one-off bootstrap)

```bash
cd bicep
az login && az account set --subscription "<sub>"

# Edit main.bicepparam with your values, then:
az deployment sub create \
  --name tfstate-bootstrap \
  --location australiaeast \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### Terraform

```bash
cd terraform
az login && az account set --subscription "<sub>"
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

# Create terraform.tfvars with your values, then:
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

See the implementation-specific READMEs for full details:
- [Terraform README](./terraform/README.md)
- [Bicep README](./bicep/README.md)

---

## Using the backend

Once deployed, configure your consuming Terraform project:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-<your-storage-account>"
    storage_account_name = "<your-storage-account>"
    container_name       = "tfstate"
    key                  = "<workload>.tfstate"
    use_azuread_auth     = true
  }
}
```

Shared-key access is disabled — authenticate via `az login`, managed identity, or OIDC before running `terraform init`.

---

## CI/CD

Both pipelines are manual-dispatch and authenticate via workload identity federation (OIDC):

- **GitHub Actions** — [`.github/workflows/deploy.yml`](./.github/workflows/deploy.yml)
- **Azure Pipelines** — [`azure-pipelines.yml`](./azure-pipelines.yml)

Each pipeline lets you choose either the Bicep or Terraform implementation at dispatch time.

---

## Prerequisites

- **Azure CLI** ≥ 2.60
- **Terraform** ≥ 1.10 (for the Terraform implementation)
- **Bicep CLI** ≥ 0.30 (for the Bicep implementation; bundled with Azure CLI)
- Subscription-level permissions: `Contributor` + `User Access Administrator`

---

## Repository layout

```
.
├── README.md
├── CLAUDE.md                 # AI agent guidance
├── INSTRUCTIONS.md           # Contributor task instructions
├── .github/
│   ├── copilot-instructions.md
│   └── workflows/deploy.yml  # GitHub Actions pipeline
├── azure-pipelines.yml       # Azure DevOps pipeline
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── versions.tf
│   └── README.md
└── bicep/
    ├── main.bicep
    ├── main.bicepparam
    └── README.md
```

---

## License

See [LICENSE](./LICENSE).
