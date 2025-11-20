# Azure Storage Account with Data Lake Gen2 capabilities

resource "azurerm_storage_account" "main" {
  name                     = replace("${var.project_name}sa${local.resource_suffix}", "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  is_hns_enabled           = true # Hierarchical namespace for Data Lake Gen2

  # Security settings
  enable_https_traffic_only       = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Network rules
  network_rules {
    default_action = "Allow" # Change to "Deny" in production with specific IP whitelisting
    bypass         = ["AzureServices"]
  }

  tags = local.common_tags
}

# Bronze Container - Raw data ingestion
resource "azurerm_storage_container" "bronze" {
  name                  = "bronze"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Silver Container - Cleaned and validated data
resource "azurerm_storage_container" "silver" {
  name                  = "silver"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Gold Container - Business-ready aggregated data
resource "azurerm_storage_container" "gold" {
  name                  = "gold"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Scripts Container - Store pipeline scripts and configs
resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create folder structure in bronze container
resource "azurerm_storage_blob" "bronze_transactions_folder" {
  name                   = "transactions/.placeholder"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.bronze.name
  type                   = "Block"
  source_content         = "placeholder"
}

resource "azurerm_storage_blob" "bronze_customers_folder" {
  name                   = "customers/.placeholder"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.bronze.name
  type                   = "Block"
  source_content         = "placeholder"
}

# Storage account keys - used by Data Factory and Databricks
resource "azurerm_key_vault_secret" "storage_account_key" {
  name         = "storage-account-key"
  value        = azurerm_storage_account.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [
    azurerm_role_assignment.terraform_kv_admin
  ]
}

resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [
    azurerm_role_assignment.terraform_kv_admin
  ]
}
