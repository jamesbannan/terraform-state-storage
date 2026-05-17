# CLAUDE.md

Guidance for AI coding agents (Claude, Copilot, etc.) working in this repository.

## Purpose

This repository bootstraps a **WAF-aligned Azure Storage Account** intended for use as a **Terraform remote state backend**. Two parallel IaC implementations are provided:

- `terraform/` — Terraform configuration
- `bicep/` — Bicep configuration

Both implementations must produce a functionally equivalent deployment.

## Hard Constraints

1. **Azure Verified Modules (AVM) only.** All Azure resources MUST be deployed via published Azure Verified Modules. Do not author raw `azurerm_*` / `Microsoft.*` resources directly when an AVM resource or pattern module exists.
   - Terraform: use modules from the [Azure/terraform-azurerm-avm-*](https://registry.terraform.io/namespaces/Azure) registry namespace (resource modules `avm-res-*` and pattern modules `avm-ptn-*`).
   - Bicep: use modules from the public Bicep registry under `br/public:avm/res/*` and `br/public:avm/ptn/*`.
   - Pin every AVM module to an explicit version. Never use floating tags.
2. **WAF alignment.** The deployed storage account must follow Microsoft's Well-Architected Framework recommendations for security, reliability, and operational excellence (see "WAF Defaults" below).
3. **No secrets in source.** Never commit credentials, SAS tokens, account keys, subscription IDs, or tenant IDs. Use variables / parameters.
4. **Parity.** Changes to one implementation (Terraform or Bicep) should be mirrored in the other unless explicitly scoped otherwise.

## WAF Defaults (must be enforced)

The storage account configuration must, at minimum:

- Use `Standard_ZRS` or higher redundancy (`Standard_GZRS` for multi-region resilience where applicable).
- Set `kind = StorageV2` and `accessTier = Hot`.
- Require `minTlsVersion = TLS1_2` (prefer `TLS1_3` where supported).
- Disable shared-key / account-key access (`allowSharedKeyAccess = false`) — authenticate via Entra ID / RBAC.
- Disable public blob access (`allowBlobPublicAccess = false`).
- Set `publicNetworkAccess = Disabled` and expose via **private endpoint** for the `blob` sub-resource (or restrict via network rules when private endpoints are out of scope for the consumer).
- Enable **infrastructure encryption** and use a **customer-managed key** when the consumer provides a Key Vault; otherwise fall back to Microsoft-managed keys with a documented note.
- Enable **blob versioning**, **soft delete for blobs** (>=7 days) and **soft delete for containers** (>=7 days), **change feed**, and **point-in-time restore** consistent with backend-state needs.
- Create a dedicated container (default name: `tfstate`) with `publicAccess = None`.
- Enable **diagnostic settings** sending `StorageRead`, `StorageWrite`, `StorageDelete`, and `AllMetrics` to a Log Analytics workspace when one is provided.
- Apply a system-assigned managed identity by default.
- Apply Azure RBAC role assignments (e.g., `Storage Blob Data Contributor`) for the Terraform principal(s) — do not rely on keys.
- Apply resource tags from a single input/parameter map.

Any deviation from the above must be a deliberate, documented input toggle with a secure default.

## Repository Layout (target)

```
.
├── README.md
├── CLAUDE.md
├── INSTRUCTIONS.md
├── terraform/
│   ├── main.tf            # composes AVM modules
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── versions.tf
│   └── examples/
└── bicep/
    ├── main.bicep         # composes AVM modules
    ├── main.bicepparam
    └── examples/
```

## Conventions

- **Naming:** Resource names follow CAF abbreviations (`st`, `rg`, `kv`, `law`, `pe`) and accept a workload/environment prefix via input.
- **Inputs:** Required inputs are `location`, `resource_group_name` (or `create_resource_group` toggle), `name_prefix`, `tags`. Optional inputs gate private endpoint, CMK, Log Analytics, and network rules.
- **Outputs:** Always export `storage_account_id`, `storage_account_name`, `resource_group_name`, `container_name`, and the `backend` configuration block (Terraform) or equivalent (Bicep).
- **Versions:** Pin Terraform `>= 1.9`, `azurerm` provider `~> 4.0`, Bicep CLI `>= 0.30`. Pin every AVM module version.
- **Formatting:** Run `terraform fmt -recursive` and `bicep format` before committing.
- **Validation:** Run `terraform validate` and `bicep build` (or `az bicep build`) for every change.

## Useful Commands

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

## What Not To Do

- Do **not** introduce a non-AVM Azure resource when an AVM module exists for it.
- Do **not** loosen WAF defaults (public network access, shared keys, TLS downgrade, etc.) silently.
- Do **not** add CI, linters, tests, or tooling unless asked — keep changes scoped.
- Do **not** rewrite the other implementation when only one was requested, but flag the drift to the user.
- Do **not** commit `.tfstate`, `.tfvars`, `.bicepparam` files containing real values, or `.terraform/` directories (see `.gitignore`).

## When Unsure

Ask the user. Prefer clarifying questions over assumptions for: target subscription topology, whether a Key Vault / Log Analytics workspace already exists, private endpoint VNet/subnet ownership, and which identity will run Terraform.
