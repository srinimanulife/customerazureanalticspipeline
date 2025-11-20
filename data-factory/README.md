# Azure Data Factory - JSON Definitions

This folder contains JSON definitions for the Azure Data Factory pipeline, datasets, and linked services. These files can be used for:

1. **Documentation**: Understanding the pipeline structure
2. **Manual Import**: Importing into Data Factory via the UI
3. **Git Integration**: Using ADF's native Git integration
4. **ARM Templates**: Converting to ARM templates for deployment

## Files

### 1. pipeline.json
Main orchestration pipeline with the following activities:
- **CheckNewFiles**: GetMetadata activity to check for new files in Bronze
- **TransformBronzeToSilver**: Databricks notebook for data cleaning
- **TransformSilverToGold**: Databricks notebook for business aggregations
- **LogPipelineSuccess/Failure**: Logging activities

**Parameters:**
- `storageAccountName`: Name of the storage account
- `pipelineRunDate`: Date of pipeline run (defaults to current date)

### 2. datasets.json
Dataset definitions for all data layers:
- **BronzeTransactionsCsv**: Raw CSV files in Bronze container
- **SilverTransactionsParquet**: Cleaned Parquet files in Silver container
- **GoldDailySalesDelta**: Aggregated Delta table for daily sales
- **GoldCustomerSegmentationDelta**: Delta table for customer segments

### 3. linked-services.json
Linked service definitions:
- **LinkedServiceBlobStorage**: Connection to Azure Storage using managed identity
- **LinkedServiceDatabricks**: Connection to Databricks workspace
- **LinkedServiceKeyVault**: Connection to Key Vault for secrets
- **LinkedServiceSynapse**: Connection to Synapse Analytics

**Integration Runtime:**
- **AutoResolveIntegrationRuntime**: Managed IR in US Gov Virginia

## Important Notes for Azure Government Cloud

### Endpoints
All JSON files use Azure Government Cloud endpoints:
- Storage: `*.blob.core.usgovcloudapi.net`
- Key Vault: `*.vault.usgovcloudapi.net`
- Synapse: `*.sql.azuresynapse.usgovcloudapi.net`

### Placeholders to Replace
Before using these files, replace the following placeholders:
- `<storage-account-name>`: Your storage account name
- `<databricks-workspace-url>`: Your Databricks workspace URL
- `<subscription-id>`: Your Azure subscription ID
- `<resource-group>`: Your resource group name
- `<workspace-name>`: Your Databricks workspace name
- `<keyvault-name>`: Your Key Vault name
- `<synapse-workspace>`: Your Synapse workspace name

## Usage Options

### Option 1: Terraform (Recommended)
The Terraform code in `../terraform/data-factory.tf` already creates these resources. Use that for infrastructure as code deployment.

```bash
cd ../terraform
terraform init
terraform apply
```

### Option 2: Azure CLI
Deploy using Azure CLI:

```bash
# Create Data Factory
az datafactory create \
  --factory-name customer-analytics-adf \
  --resource-group customer-analytics-rg \
  --location usgovvirginia

# Create linked services
az datafactory linked-service create \
  --factory-name customer-analytics-adf \
  --resource-group customer-analytics-rg \
  --name LinkedServiceBlobStorage \
  --properties @linked-services.json

# Create datasets
az datafactory dataset create \
  --factory-name customer-analytics-adf \
  --resource-group customer-analytics-rg \
  --name BronzeTransactionsCsv \
  --properties @datasets.json

# Create pipeline
az datafactory pipeline create \
  --factory-name customer-analytics-adf \
  --resource-group customer-analytics-rg \
  --name CustomerAnalyticsPipeline \
  --pipeline @pipeline.json
```

### Option 3: Data Factory Studio UI
1. Open Data Factory Studio: https://adf.azure.us
2. Go to "Manage" → "Git configuration" (optional)
3. Go to "Author" → "+" → "Import from pipeline template"
4. Upload the JSON files
5. Update connection strings and parameters

### Option 4: Git Integration
If using ADF's native Git integration:

1. In Data Factory Studio, go to "Manage" → "Git configuration"
2. Connect to your Azure DevOps or GitHub repo
3. Place these JSON files in the appropriate folders:
   - `pipeline/CustomerAnalyticsPipeline.json`
   - `dataset/BronzeTransactionsCsv.json`
   - `linkedService/LinkedServiceBlobStorage.json`
4. ADF will automatically sync

**Note**: For Azure Government, use Azure DevOps Government instance.

## Trigger Configuration

### Schedule Trigger (Daily at 2 AM)
```json
{
  "name": "DailyTrigger",
  "properties": {
    "type": "ScheduleTrigger",
    "typeProperties": {
      "recurrence": {
        "frequency": "Day",
        "interval": 1,
        "startTime": "2025-01-19T02:00:00Z",
        "timeZone": "UTC",
        "schedule": {
          "hours": [2],
          "minutes": [0]
        }
      }
    },
    "pipelines": [
      {
        "pipelineReference": {
          "referenceName": "CustomerAnalyticsPipeline",
          "type": "PipelineReference"
        }
      }
    ]
  }
}
```

Create trigger via CLI:
```bash
az datafactory trigger create \
  --factory-name customer-analytics-adf \
  --resource-group customer-analytics-rg \
  --name DailyTrigger \
  --properties @trigger.json
```

## Testing the Pipeline

### Manual Trigger
```bash
# Trigger pipeline run
az datafactory pipeline create-run \
  --factory-name customer-analytics-adf \
  --resource-group customer-analytics-rg \
  --name CustomerAnalyticsPipeline \
  --parameters storageAccountName=customersadev123456

# Check run status
az datafactory pipeline-run show \
  --factory-name customer-analytics-adf \
  --resource-group customer-analytics-rg \
  --run-id <run-id>
```

### Debug in UI
1. Open pipeline in Data Factory Studio
2. Click "Debug"
3. Provide parameter values
4. Monitor execution

## Monitoring

### View Pipeline Runs
```bash
# List recent runs
az datafactory pipeline-run query-by-factory \
  --factory-name customer-analytics-adf \
  --resource-group customer-analytics-rg \
  --last-updated-after "2025-01-01" \
  --last-updated-before "2025-12-31"
```

### View in Portal
1. Go to https://portal.azure.us
2. Navigate to Data Factory resource
3. Click "Monitor" in left menu
4. View pipeline runs, activity runs, and trigger runs

### Alerts
Configure alerts in Azure Monitor:
```bash
az monitor metrics alert create \
  --name adf-failed-runs \
  --resource-group customer-analytics-rg \
  --scopes /subscriptions/<sub-id>/resourceGroups/customer-analytics-rg/providers/Microsoft.DataFactory/factories/customer-analytics-adf \
  --condition "count PipelineFailedRuns > 0" \
  --description "Alert when pipeline fails"
```

## Best Practices

1. **Use Managed Identity**: Avoid storing credentials in linked services
2. **Parameterize**: Use pipeline parameters for flexibility
3. **Version Control**: Store JSON in Git
4. **Testing**: Test in dev environment first
5. **Monitoring**: Set up alerts for failures
6. **Documentation**: Keep this README updated

## Troubleshooting

### Common Issues

**Issue**: "Authentication failed"
- **Solution**: Ensure Data Factory managed identity has proper RBAC roles on resources

**Issue**: "Dataset not found"
- **Solution**: Verify linked service connection and dataset path

**Issue**: "Databricks notebook not found"
- **Solution**: Ensure notebooks are deployed to correct path in Databricks

**Issue**: "Region not supported"
- **Solution**: Verify all resources are in US Gov Virginia region

## Related Files

- **Terraform**: `../terraform/data-factory.tf` - IaC definition
- **Databricks**: `../databricks/notebooks/` - Notebook code
- **Synapse**: `../synapse/sql-scripts/` - SQL scripts
- **Documentation**: `../docs/INTERVIEW_QA.md` - Questions about Data Factory

## Interview Talking Points

Key points to discuss about this Data Factory implementation:

1. **Orchestration**: How pipeline coordinates Bronze → Silver → Gold transformations
2. **Error Handling**: Retry logic and failure notifications
3. **Parameterization**: Dynamic execution with parameters
4. **Integration**: How it connects Storage, Databricks, and Synapse
5. **Monitoring**: How to track pipeline health and failures
6. **Security**: Managed identity authentication, no stored credentials
7. **Scheduling**: Daily trigger at 2 AM with ability to run ad-hoc
8. **Gov Cloud**: Proper endpoints and compliance considerations

## Additional Resources

- [Azure Data Factory Documentation](https://docs.microsoft.com/en-us/azure/data-factory/)
- [Azure Government Data Factory](https://docs.microsoft.com/en-us/azure/azure-government/documentation-government-services-dataanalytics#azure-data-factory)
- [ADF JSON Reference](https://docs.microsoft.com/en-us/azure/data-factory/concepts-pipelines-activities)
