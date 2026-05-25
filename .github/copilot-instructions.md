# Copilot Instructions

## Architecture

This repository bootstraps a **WAF-aligned Azure Storage Account** for Terraform remote state. Two parallel IaC implementations exist under `terraform/` and `bicep/` — both must produce functionally equivalent deployments and stay at parity (same inputs, resources, outputs).

All Azure resources **must** be deployed via pinned [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/):
- Terraform: `Azure/avm-res-*` and `Azure/avm-ptn-*` from the Terraform Registry
- Bicep: `br/public:avm/res/*` and `br/public:avm/ptn/*` from the public Bicep registry

Do not author raw `azurerm_*` or `Microsoft.*` resources when an AVM module exists.

## Validation Commands

```bash
# Terraform
cd terraform
terraform fmt -recursive
terraform init -backend=false
terraform validate

# Bicep
cd bicep
az bicep format --file main.bicep
az bicep build --file main.bicep
```

Run `terraform fmt -check -recursive` and `az bicep build` for every change before committing.

## Key Conventions

- **Naming**: Follow CAF abbreviations (`st`, `rg`, `kv`, `law`, `pe`) with a workload/environment prefix from input.
- **Module versions**: Pin every AVM module to an explicit semver — never use floating tags.
- **Version constraints**: Terraform `>= 1.9`, `azurerm` provider `~> 4.0`, Bicep CLI `>= 0.30`.
- **No secrets in source**: Never commit credentials, SAS tokens, account keys, subscription IDs, or tenant IDs. Use variables/parameters.
- **Required outputs**: `resource_group_name`, `storage_account_id`, `storage_account_name`, `container_name`, `backend_config`.

## WAF Defaults (non-negotiable)

These security/reliability settings must always be enforced — never weaken silently:

- `Standard_ZRS` redundancy minimum
- `StorageV2` / `Hot` access tier
- `minTlsVersion = TLS1_2` (prefer TLS1_3)
- `allowSharedKeyAccess = false` (Entra ID / RBAC only)
- `allowBlobPublicAccess = false`
- Network default action `Deny` with Azure Services bypass
- Infrastructure encryption enabled
- Blob versioning, change feed, soft delete (≥7 days) for blobs and containers
- Container access type `None`
- System-assigned managed identity
- RBAC role assignments (`Storage Blob Data Contributor`) for deploying principals

Any input that weakens a default must itself default to the secure value.

## CI/CD

- **GitHub Actions**: `.github/workflows/deploy.yml` — manual dispatch, OIDC auth, runs either Bicep or Terraform
- **Azure Pipelines**: `azure-pipelines.yml` — mirrors the GitHub workflow with ADO service connections

Both pipelines authenticate via workload identity federation (OIDC). Never run `terraform apply` or `az deployment create` locally as part of authoring.

## When Modifying

1. Mirror changes across both `terraform/` and `bicep/` unless explicitly scoped to one.
2. Verify the latest published AVM module version before pinning.
3. Run validation commands for both implementations.
4. Do not add CI, linters, tests, or tooling unless asked.
