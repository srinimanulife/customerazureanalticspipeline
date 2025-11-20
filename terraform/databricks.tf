# Azure Databricks Workspace

resource "azurerm_databricks_workspace" "main" {
  name                = "${var.project_name}-dbw-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.databricks_sku

  # Enable Premium features
  public_network_access_enabled = true # Set to false for private endpoints in production

  tags = local.common_tags
}

# Configure Databricks provider for workspace resources
provider "databricks" {
  host = azurerm_databricks_workspace.main.workspace_url
}

# Databricks Secret Scope backed by Azure Key Vault
resource "databricks_secret_scope" "kv_backed" {
  name = "azure-key-vault-secrets"

  keyvault_metadata {
    resource_id = azurerm_key_vault.main.id
    dns_name    = azurerm_key_vault.main.vault_uri
  }

  depends_on = [azurerm_databricks_workspace.main]
}

# Databricks Cluster for data processing
resource "databricks_cluster" "shared_autoscaling" {
  cluster_name            = "Shared Autoscaling Cluster"
  spark_version           = var.databricks_cluster_version
  node_type_id            = "Standard_DS3_v2"
  autotermination_minutes = 20

  autoscale {
    min_workers = 1
    max_workers = 4
  }

  spark_conf = {
    "spark.databricks.delta.preview.enabled"          = "true"
    "spark.databricks.cluster.profile"                = "serverless"
    "spark.databricks.repl.allowedLanguages"          = "python,sql"
  }

  azure_attributes {
    availability       = "ON_DEMAND_AZURE"
    first_on_demand    = 1
    spot_bid_max_price = -1
  }

  library {
    pypi {
      package = "pandas"
    }
  }

  library {
    pypi {
      package = "azure-storage-blob"
    }
  }

  depends_on = [azurerm_databricks_workspace.main]
}

# Service Principal for Databricks to access storage
resource "azuread_application" "databricks_sp" {
  display_name = "${var.project_name}-databricks-sp"
}

resource "azuread_service_principal" "databricks_sp" {
  client_id = azuread_application.databricks_sp.client_id
}

resource "azuread_service_principal_password" "databricks_sp" {
  service_principal_id = azuread_service_principal.databricks_sp.object_id
}

# Grant Databricks SP access to storage
resource "azurerm_role_assignment" "databricks_storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.databricks_sp.object_id
}

# Store service principal credentials in Key Vault
resource "azurerm_key_vault_secret" "databricks_sp_client_id" {
  name         = "databricks-sp-client-id"
  value        = azuread_application.databricks_sp.client_id
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.terraform_kv_admin]
}

resource "azurerm_key_vault_secret" "databricks_sp_client_secret" {
  name         = "databricks-sp-client-secret"
  value        = azuread_service_principal_password.databricks_sp.value
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.terraform_kv_admin]
}

# Databricks workspace directory for notebooks
resource "databricks_directory" "pipelines" {
  path = "/Shared/pipelines"

  depends_on = [azurerm_databricks_workspace.main]
}
