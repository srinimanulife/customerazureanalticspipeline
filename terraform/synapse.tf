# Azure Synapse Analytics Workspace

# Storage account for Synapse workspace (required)
resource "azurerm_storage_account" "synapse" {
  name                     = replace("${var.project_name}synapse${local.resource_suffix}", "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true

  tags = local.common_tags
}

resource "azurerm_storage_data_lake_gen2_filesystem" "synapse" {
  name               = "synapse"
  storage_account_id = azurerm_storage_account.synapse.id
}

# Synapse Workspace
resource "azurerm_synapse_workspace" "main" {
  name                                 = "${var.project_name}-synapse-${local.resource_suffix}"
  resource_group_name                  = azurerm_resource_group.main.name
  location                             = azurerm_resource_group.main.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse.id
  sql_administrator_login              = var.synapse_sql_admin_username
  sql_administrator_login_password     = var.synapse_sql_admin_password

  # Enable managed virtual network
  managed_virtual_network_enabled = false # Set to true for enhanced security

  # AAD authentication
  aad_admin {
    login     = azuread_group.admins.display_name
    object_id = azuread_group.admins.object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Firewall rules - Allow Azure services
resource "azurerm_synapse_firewall_rule" "allow_azure_services" {
  name                 = "AllowAllWindowsAzureIps"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "0.0.0.0"
}

# Firewall rules - Allow all (for demo, restrict in production)
resource "azurerm_synapse_firewall_rule" "allow_all" {
  name                 = "AllowAll"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "255.255.255.255"
}

# Grant Synapse managed identity access to data lake storage
resource "azurerm_role_assignment" "synapse_storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_synapse_workspace.main.identity[0].principal_id
}

# Synapse Spark Pool for big data processing
resource "azurerm_synapse_spark_pool" "main" {
  name                 = "spark${replace(local.resource_suffix, "-", "")}"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  node_size_family     = "MemoryOptimized"
  node_size            = "Small"

  auto_scale {
    max_node_count = 5
    min_node_count = 3
  }

  auto_pause {
    delay_in_minutes = 15
  }

  spark_version = "3.3"

  tags = local.common_tags
}

# Synapse SQL Pool (Dedicated) - Optional, comment out to save costs
# Uncomment for production use with dedicated SQL pool
# resource "azurerm_synapse_sql_pool" "main" {
#   name                 = "sqldw${replace(local.resource_suffix, "-", "")}"
#   synapse_workspace_id = azurerm_synapse_workspace.main.id
#   sku_name             = "DW100c"
#   create_mode          = "Default"
#
#   tags = local.common_tags
# }

# Linked Service to connect Synapse to main storage account
resource "azurerm_synapse_linked_service" "storage" {
  name                 = "LinkedServiceStorage"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  type                 = "AzureBlobStorage"
  type_properties_json = jsonencode({
    connectionString = azurerm_storage_account.main.primary_connection_string
  })

  depends_on = [
    azurerm_synapse_firewall_rule.allow_azure_services
  ]
}

# Store Synapse credentials in Key Vault
resource "azurerm_key_vault_secret" "synapse_sql_admin_password" {
  name         = "synapse-sql-admin-password"
  value        = var.synapse_sql_admin_password
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.terraform_kv_admin]
}
