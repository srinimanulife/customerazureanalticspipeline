# Azure Key Vault for storing secrets

resource "azurerm_key_vault" "main" {
  name                       = "${var.project_name}-kv-${local.resource_suffix}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # Set to true in production

  # Enable RBAC for access control
  enable_rbac_authorization = true

  network_acls {
    default_action = "Allow" # Change to "Deny" in production
    bypass         = "AzureServices"
  }

  tags = local.common_tags
}

# Grant Terraform service principal access to Key Vault
resource "azurerm_role_assignment" "terraform_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant Data Engineers access to Key Vault secrets
resource "azurerm_role_assignment" "engineers_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_group.data_engineers.object_id
}

# Grant Admins full access to Key Vault
resource "azurerm_role_assignment" "admins_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azuread_group.admins.object_id
}
