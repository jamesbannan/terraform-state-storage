# INSTRUCTIONS.md

Task-oriented instructions for contributors and AI agents implementing or modifying the IaC in this repository.

> Read [`CLAUDE.md`](./CLAUDE.md) first — it defines the binding constraints (AVM-only, WAF defaults, parity between Terraform and Bicep). This file describes **how** to carry out work within those rules.

## 1. Scope

Deliver a deployable, WAF-aligned Azure Storage Account suitable as a Terraform remote state backend, implemented twice:

- **Terraform** — under `terraform/`, composing Azure Verified Modules from the `Azure/terraform-azurerm-avm-*` namespace.
- **Bicep** — under `bicep/`, composing Azure Verified Modules from `br/public:avm/res/*` and `br/public:avm/ptn/*`.

Both implementations expose the same inputs, produce the same resources, and emit the same outputs.

## 2. Required Azure Verified Modules

Use AVM resource (`avm-res-*` / `avm/res/*`) or pattern (`avm-ptn-*` / `avm/ptn/*`) modules for every resource. At minimum the solution composes:

| Capability | Terraform AVM module | Bicep AVM module |
|---|---|---|
| Resource Group | `Azure/avm-res-resources-resourcegroup/azurerm` | `br/public:avm/res/resources/resource-group` |
| Storage Account (+ blob services, container, diagnostic settings, RBAC) | `Azure/avm-res-storage-storageaccount/azurerm` | `br/public:avm/res/storage/storage-account` |
| Private Endpoint (if not handled inline by the storage module) | `Azure/avm-res-network-privateendpoint/azurerm` | `br/public:avm/res/network/private-endpoint` |
| Private DNS Zone (`privatelink.blob.core.windows.net`) | `Azure/avm-res-network-privatednszone/azurerm` | `br/public:avm/res/network/private-dns-zone` |
| Key Vault (only if CMK requested) | `Azure/avm-res-keyvault-vault/azurerm` | `br/public:avm/res/key-vault/vault` |

Confirm the latest published version on the [Terraform Registry](https://registry.terraform.io/namespaces/Azure) and [MCR / Bicep public registry](https://mcr.microsoft.com/catalog?cat=Bicep) before pinning. Always pin to an explicit semver.

Do not introduce additional modules without first checking AVM coverage. If no AVM module exists for a needed resource, stop and ask the user before authoring a raw resource.

## 3. Inputs (both implementations)

Required:

- `location` — Azure region.
- `name_prefix` — short workload/environment identifier used for CAF naming (e.g., `tfstateprd`).
- `tags` — map/object of resource tags.

Optional (with secure defaults):

- `resource_group_name` — when omitted, create one named via `name_prefix`.
- `container_name` — defaults to `tfstate`.
- `account_replication_type` — defaults to `ZRS`.
- `enable_private_endpoint` — defaults to `true`. Requires `private_endpoint_subnet_id` and optionally `private_dns_zone_resource_group_id`.
- `enable_customer_managed_key` — defaults to `false`. When `true`, deploy/reference a Key Vault and configure CMK on the storage account.
- `log_analytics_workspace_id` — when set, attach diagnostic settings.
- `rbac_principal_ids` — list of object IDs to grant `Storage Blob Data Contributor` on the storage account.

## 4. Outputs (both implementations)

- `resource_group_name`
- `storage_account_id`
- `storage_account_name`
- `container_name`
- `backend_config` — an object containing `resource_group_name`, `storage_account_name`, `container_name`, and `use_azuread_auth = true`, ready to be consumed by a Terraform `backend "azurerm"` block.

## 5. WAF Defaults (non-negotiable)

The Storage Account composition must set:

- `account_kind = StorageV2`, `access_tier = Hot`.
- `min_tls_version = TLS1_2` (use `TLS1_3` when the module supports it).
- `shared_access_key_enabled = false`.
- `allow_nested_items_to_be_public = false` / `allowBlobPublicAccess = false`.
- `public_network_access_enabled = false` when private endpoint is enabled; otherwise use a deny-by-default network ruleset with explicit allowed subnets/IPs supplied by inputs.
- `infrastructure_encryption_enabled = true`.
- Blob service: `versioning_enabled = true`, `change_feed_enabled = true`, `blob_soft_delete_retention_days >= 7`, `container_soft_delete_retention_days >= 7`.
- Container: `container_access_type = None`.
- Identity: system-assigned managed identity enabled.
- Diagnostic settings emit `StorageRead`, `StorageWrite`, `StorageDelete`, and `AllMetrics` when a workspace is supplied.
- RBAC: assign `Storage Blob Data Contributor` to `rbac_principal_ids`.

Any input that weakens these defaults must default to the secure value and be documented inline.

## 6. Workflow

1. **Plan in one place.** Decide on resource graph and AVM module versions before editing files. Mirror the change in the sibling implementation.
2. **Edit Terraform.**
   ```bash
   cd terraform
   terraform fmt -recursive
   terraform init -backend=false
   terraform validate
   ```
3. **Edit Bicep.**
   ```bash
   cd bicep
   az bicep format --file main.bicep
   az bicep build --file main.bicep
   ```
4. **Do not run `terraform apply` or `az deployment ... create`** against a real subscription as part of authoring. Deployment is the consumer's responsibility.
5. **Commit** with a focused message. Do not include generated files (`.terraform/`, `*.tfstate*`, compiled ARM JSON from `bicep build`) — `.gitignore` should already cover these; extend it if needed.

## 7. Definition of Done

A change is complete when:

- [ ] Every Azure resource is produced by a pinned AVM module.
- [ ] All WAF defaults in §5 are enforced.
- [ ] Terraform passes `terraform fmt -check -recursive` and `terraform validate`.
- [ ] Bicep passes `az bicep build` with no warnings introduced by this change.
- [ ] Terraform and Bicep implementations are at parity (same inputs, resources, outputs).
- [ ] README usage examples (if present) still reflect the actual interface.
- [ ] No secrets, subscription IDs, tenant IDs, or real principal IDs are committed.

## 8. Out of Scope (unless explicitly requested)

- CI/CD pipelines, pre-commit hooks, or test harnesses.
- Multi-region active/active replication beyond `GZRS`.
- Bootstrapping the consumer's Terraform configuration (this repo only produces the backend).
- Networking infrastructure (VNets, subnets, firewalls) — these are inputs, not deliverables.

## 9. Asking for Clarification

Before implementing, ask the user when any of the following are unclear:

- Target subscription / management group placement.
- Whether a private endpoint subnet and Private DNS zone already exist, and in which subscription.
- Whether a Key Vault for CMK already exists, or should be created here.
- The identity (SPN, managed identity, user) that will run Terraform against this backend.
- Naming convention overrides beyond CAF defaults.
