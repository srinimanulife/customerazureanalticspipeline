# Azure Data Factory

resource "azurerm_data_factory" "main" {
  name                = "${var.project_name}-adf-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Grant Data Factory managed identity access to storage
resource "azurerm_role_assignment" "adf_storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.main.identity[0].principal_id
}

# Grant Data Factory access to Key Vault for secrets
resource "azurerm_role_assignment" "adf_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_data_factory.main.identity[0].principal_id
}

# Linked Service - Azure Blob Storage
resource "azurerm_data_factory_linked_service_azure_blob_storage" "main" {
  name              = "LinkedServiceBlobStorage"
  data_factory_id   = azurerm_data_factory.main.id
  use_managed_identity = true
  service_endpoint  = azurerm_storage_account.main.primary_blob_endpoint
}

# Linked Service - Databricks
resource "azurerm_data_factory_linked_service_azure_databricks" "main" {
  name                = "LinkedServiceDatabricks"
  data_factory_id     = azurerm_data_factory.main.id
  description         = "Linked service to Databricks workspace"
  adb_domain          = "https://${azurerm_databricks_workspace.main.workspace_url}"

  msi_work_space_resource_id = azurerm_databricks_workspace.main.id

  new_cluster_config {
    node_type             = "Standard_DS3_v2"
    cluster_version       = var.databricks_cluster_version
    min_workers           = 1
    max_workers           = 2
    driver_node_type      = "Standard_DS3_v2"
    log_destination       = "dbfs:/logs"

    spark_config = {
      "spark.speculation" = "true"
    }
  }
}

# Linked Service - Key Vault
resource "azurerm_data_factory_linked_service_key_vault" "main" {
  name            = "LinkedServiceKeyVault"
  data_factory_id = azurerm_data_factory.main.id
  key_vault_id    = azurerm_key_vault.main.id
}

# Dataset - Bronze (Source CSV files)
resource "azurerm_data_factory_dataset_delimited_text" "bronze_csv" {
  name                = "BronzeTransactionsCsv"
  data_factory_id     = azurerm_data_factory.main.id
  linked_service_name = azurerm_data_factory_linked_service_azure_blob_storage.main.name

  azure_blob_storage_location {
    container = azurerm_storage_container.bronze.name
    path      = "transactions"
    filename  = "*.csv"
  }

  column_delimiter    = ","
  row_delimiter       = "\n"
  encoding            = "UTF-8"
  quote_character     = "\""
  escape_character    = "\\"
  first_row_as_header = true
}

# Dataset - Silver (Parquet files)
resource "azurerm_data_factory_dataset_parquet" "silver_parquet" {
  name                = "SilverTransactionsParquet"
  data_factory_id     = azurerm_data_factory.main.id
  linked_service_name = azurerm_data_factory_linked_service_azure_blob_storage.main.name

  azure_blob_storage_location {
    container = azurerm_storage_container.silver.name
    path      = "transactions"
  }

  compression_codec = "snappy"
}

# Pipeline - Main orchestration pipeline
resource "azurerm_data_factory_pipeline" "main" {
  name            = "CustomerAnalyticsPipeline"
  data_factory_id = azurerm_data_factory.main.id
  description     = "End-to-end pipeline for customer analytics"

  activities_json = jsonencode([
    {
      name = "CheckNewFiles"
      type = "GetMetadata"
      dependsOn = []
      policy = {
        timeout = "0.12:00:00"
        retry   = 0
      }
      userProperties = []
      typeProperties = {
        dataset = {
          referenceName = azurerm_data_factory_dataset_delimited_text.bronze_csv.name
          type          = "DatasetReference"
        }
        fieldList = ["exists", "lastModified"]
      }
    },
    {
      name = "TransformBronzeToSilver"
      type = "DatabricksNotebook"
      dependsOn = [
        {
          activity        = "CheckNewFiles"
          dependencyConditions = ["Succeeded"]
        }
      ]
      policy = {
        timeout = "0.12:00:00"
        retry   = 1
      }
      userProperties = []
      typeProperties = {
        notebookPath = "/Shared/pipelines/bronze_to_silver"
        baseParameters = {
          storage_account = azurerm_storage_account.main.name
          source_container = azurerm_storage_container.bronze.name
          target_container = azurerm_storage_container.silver.name
        }
      }
      linkedServiceName = {
        referenceName = azurerm_data_factory_linked_service_azure_databricks.main.name
        type          = "LinkedServiceReference"
      }
    },
    {
      name = "TransformSilverToGold"
      type = "DatabricksNotebook"
      dependsOn = [
        {
          activity        = "TransformBronzeToSilver"
          dependencyConditions = ["Succeeded"]
        }
      ]
      policy = {
        timeout = "0.12:00:00"
        retry   = 1
      }
      userProperties = []
      typeProperties = {
        notebookPath = "/Shared/pipelines/silver_to_gold"
        baseParameters = {
          storage_account = azurerm_storage_account.main.name
          source_container = azurerm_storage_container.silver.name
          target_container = azurerm_storage_container.gold.name
        }
      }
      linkedServiceName = {
        referenceName = azurerm_data_factory_linked_service_azure_databricks.main.name
        type          = "LinkedServiceReference"
      }
    }
  ])
}

# Trigger - Schedule daily at 2 AM
resource "azurerm_data_factory_trigger_schedule" "daily" {
  name            = "DailyTrigger"
  data_factory_id = azurerm_data_factory.main.id
  pipeline_name   = azurerm_data_factory_pipeline.main.name

  interval  = 1
  frequency = "Day"

  schedule {
    hours   = [2]
    minutes = [0]
  }

  # Set to false initially, enable after testing
  activated = false
}
