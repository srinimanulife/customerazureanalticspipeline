# Sample Data for Testing

This folder contains sample transaction data for testing the Azure Data Platform pipeline.

## File: transactions-sample.csv

**Description**: Sample customer transaction data with 30 records spanning 5 days (Jan 15-19, 2025)

**Schema**:
- `transaction_id`: Unique transaction identifier (e.g., TXN001)
- `customer_id`: Customer identifier (e.g., CUST0001)
- `transaction_date`: Date of transaction (YYYY-MM-DD format)
- `amount`: Transaction amount in USD (decimal)
- `product_category`: Category of product (ELECTRONICS, CLOTHING, BOOKS, SPORTS)
- `payment_method`: Payment type (CREDIT_CARD, DEBIT_CARD, CASH)
- `store_location`: Store city name (e.g., NEW YORK)
- `quantity`: Number of items purchased (integer)

**Data Characteristics**:
- 18 unique customers
- 5 product categories
- 3 payment methods
- 16 different store locations
- Transaction amounts range from $24.99 to $399.99
- Dates span 5 consecutive days

## How to Use This Data

### Option 1: Azure Portal Upload

1. Go to https://portal.azure.us
2. Navigate to your storage account
3. Open the "bronze" container
4. Click "Upload"
5. Create folder path: `transactions/2025/01/`
6. Upload `transactions-sample.csv`

### Option 2: Azure CLI Upload

```bash
# Upload sample data to Bronze container
az storage blob upload \
  --account-name <storage-account-name> \
  --container-name bronze \
  --name transactions/2025/01/transactions-sample.csv \
  --file sample-data/transactions-sample.csv \
  --auth-mode login

# Verify upload
az storage blob list \
  --account-name <storage-account-name> \
  --container-name bronze \
  --prefix transactions/ \
  --auth-mode login
```

### Option 3: AzCopy Upload

```bash
# Login to Azure Government
azcopy login --tenant-id <tenant-id>

# Upload file
azcopy copy \
  "sample-data/transactions-sample.csv" \
  "https://<storage-account-name>.blob.core.usgovcloudapi.net/bronze/transactions/2025/01/transactions-sample.csv" \
  --recursive=false
```

### Option 4: PowerShell Upload

```powershell
# Connect to Azure Government
Connect-AzAccount -Environment AzureUSGovernment

# Set context
$storageAccount = Get-AzStorageAccount -ResourceGroupName "customer-analytics-rg" -Name "<storage-account-name>"
$ctx = $storageAccount.Context

# Upload blob
Set-AzStorageBlobContent `
  -File "sample-data/transactions-sample.csv" `
  -Container "bronze" `
  -Blob "transactions/2025/01/transactions-sample.csv" `
  -Context $ctx
```

## Testing the Pipeline

### Step 1: Upload Sample Data
Use one of the methods above to upload the sample CSV to the Bronze container.

### Step 2: Trigger the Pipeline

**Via Azure Portal:**
1. Go to Data Factory in Azure Portal
2. Open "Author & Monitor"
3. Select the pipeline
4. Click "Trigger" → "Trigger now"
5. Provide parameters if needed

**Via Azure CLI:**
```bash
az datafactory pipeline create-run \
  --factory-name customer-analytics-adf \
  --resource-group customer-analytics-rg \
  --name CustomerAnalyticsPipeline \
  --parameters storageAccountName=<storage-account-name>
```

### Step 3: Monitor Execution

**Check Pipeline Run:**
```bash
# Get latest run
az datafactory pipeline-run query-by-factory \
  --factory-name customer-analytics-adf \
  --resource-group customer-analytics-rg \
  --last-updated-after "2025-01-19T00:00:00Z" \
  --last-updated-before "2025-01-20T00:00:00Z"
```

**Monitor in Portal:**
1. Go to Data Factory
2. Click "Monitor" tab
3. View pipeline runs
4. Click on run ID to see activity details

### Step 4: Verify Results

**Check Silver Container:**
```bash
# List files in Silver
az storage blob list \
  --account-name <storage-account-name> \
  --container-name silver \
  --prefix transactions/ \
  --auth-mode login
```

**Check Gold Container:**
```bash
# List Delta tables in Gold
az storage blob list \
  --account-name <storage-account-name> \
  --container-name gold \
  --auth-mode login
```

**Query in Synapse:**
```sql
-- Check if data loaded
SELECT COUNT(*) as total_records
FROM gold.daily_sales_summary;

-- View sample data
SELECT TOP 10 *
FROM gold.daily_sales_summary
ORDER BY transaction_date DESC;

-- Check customer segmentation
SELECT
    customer_segment,
    COUNT(*) as customer_count,
    SUM(total_spent) as total_revenue
FROM gold.customer_segmentation
GROUP BY customer_segment
ORDER BY total_revenue DESC;
```

## Expected Results

After successful pipeline execution, you should see:

### Silver Container
- **Path**: `silver/transactions/transaction_date=2025-01-15/`
- **Format**: Parquet files
- **Records**: 30 (all valid)
- **Columns**: Original 8 + ingestion_timestamp + is_valid

### Gold Container

**1. daily_sales_summary/**
- 5 records (one per day: Jan 15-19)
- Aggregated metrics per day
- Example:
  ```
  transaction_date: 2025-01-19
  total_transactions: 10
  total_revenue: $1,463.88
  avg_transaction_value: $146.39
  unique_customers: 10
  ```

**2. customer_segmentation/**
- 18 records (one per customer)
- Customer segments: HIGH_VALUE, MEDIUM_VALUE, LOW_VALUE
- Frequency segments: FREQUENT, REGULAR, OCCASIONAL
- Example:
  ```
  customer_id: CUST0001
  total_transactions: 4
  total_spent: $595.46
  customer_segment: MEDIUM_VALUE
  frequency_segment: REGULAR
  ```

**3. product_category_performance/**
- 4 records (ELECTRONICS, CLOTHING, BOOKS, SPORTS)
- Revenue ranked by category
- Example:
  ```
  product_category: ELECTRONICS
  total_revenue: $2,394.85
  total_transactions: 15
  revenue_rank: 1
  ```

**4. store_performance/**
- 16 records (one per store location)
- Revenue metrics per store

**5. payment_method_analysis/**
- 3 records (CREDIT_CARD, DEBIT_CARD, CASH)
- Payment preference analysis

## Data Quality Checks

The Bronze to Silver transformation will:
- ✅ Remove duplicate transaction_ids (none in sample data)
- ✅ Filter null transaction_ids and customer_ids (none in sample)
- ✅ Filter invalid amounts (all positive in sample)
- ✅ Convert data types (string → decimal, date, int)
- ✅ Standardize category names (uppercase)
- ✅ Add quality flag (all should be TRUE)

Expected quality rate: **100%** (all 30 records valid)

## Generating More Sample Data

To generate additional test data, you can use this Python script:

```python
import pandas as pd
import random
from datetime import datetime, timedelta

# Configuration
num_records = 1000
start_date = datetime(2025, 1, 1)
end_date = datetime(2025, 1, 31)

# Sample data
categories = ['ELECTRONICS', 'CLOTHING', 'BOOKS', 'SPORTS', 'HOME']
payment_methods = ['CREDIT_CARD', 'DEBIT_CARD', 'CASH']
locations = ['NEW YORK', 'LOS ANGELES', 'CHICAGO', 'HOUSTON', 'PHOENIX']

# Generate data
data = []
for i in range(num_records):
    record = {
        'transaction_id': f'TXN{str(i+1).zfill(6)}',
        'customer_id': f'CUST{str(random.randint(1, 200)).zfill(4)}',
        'transaction_date': (start_date + timedelta(days=random.randint(0, 30))).strftime('%Y-%m-%d'),
        'amount': round(random.uniform(10, 500), 2),
        'product_category': random.choice(categories),
        'payment_method': random.choice(payment_methods),
        'store_location': random.choice(locations),
        'quantity': random.randint(1, 5)
    }
    data.append(record)

# Save to CSV
df = pd.DataFrame(data)
df.to_csv('transactions-large-sample.csv', index=False)
print(f"Generated {num_records} records")
```

## Troubleshooting

### Issue: Pipeline finds no files
**Solution**: Verify file path matches pipeline configuration:
- Pipeline expects: `bronze/transactions/*.csv`
- Your upload should be: `bronze/transactions/2025/01/transactions-sample.csv`

### Issue: Data not in Silver
**Solution**: Check Databricks notebook output for errors:
1. Go to Databricks workspace
2. Check job runs
3. View notebook output

### Issue: Gold tables empty
**Solution**:
1. Ensure Silver transformation completed successfully
2. Check Databricks logs for Silver to Gold notebook
3. Verify Data Factory pipeline completed all activities

### Issue: Synapse shows no data
**Solution**:
1. Verify external tables point to correct storage path
2. Check if Synapse managed identity has read access
3. Run: `SELECT * FROM OPENROWSET(...)` to test direct access

## Interview Talking Points

When discussing sample data testing:

1. **Data Quality**: "I validated the pipeline with 30 sample records, achieving 100% quality rate"
2. **Schema Validation**: "The sample data matches the expected schema with 8 columns"
3. **Edge Cases**: "For production, we'd add test cases for nulls, duplicates, and invalid values"
4. **Volume Testing**: "Sample has 30 records; for performance testing, I'd generate 1M+ records"
5. **Date Range**: "5 days of data allows testing of date partitioning and aggregations"
6. **Variety**: "Multiple categories, payment methods, and locations test all aggregation paths"

## Next Steps

After successful test with sample data:

1. **Larger Dataset**: Generate 10K-100K records for performance testing
2. **Error Cases**: Add test data with intentional quality issues
3. **Historical Load**: Backfill with data from past 2-3 years
4. **Real Data**: Work with business to get actual historical transactions
5. **Incremental Test**: Test incremental loading with new files each day
6. **Stress Test**: Load 1M+ records to verify scaling

## Related Files

- **Databricks Notebooks**: `../databricks/notebooks/` - Processing logic
- **Data Factory**: `../data-factory/` - Pipeline orchestration
- **Synapse Scripts**: `../synapse/sql-scripts/` - Query examples
- **Documentation**: `../docs/INTERVIEW_QA.md` - Q&A about the solution
