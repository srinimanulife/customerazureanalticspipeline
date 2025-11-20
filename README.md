# Azure Data Platform - Customer Analytics MVP

## Scenario Overview
A complete data analytics platform that ingests customer transaction data, processes it through multiple layers (Bronze → Silver → Gold), and provides analytics capabilities for business users.

## Architecture

```
Data Flow:
1. CSV files → Azure Storage (Bronze/Raw)
2. Data Factory → Orchestrates pipeline
3. Databricks → Transforms data (Silver/Gold layers)
4. Synapse Analytics → SQL access for BI tools
5. AAD Groups → Role-based access control
```

## Components

### 1. **Azure Storage Account**
- **Bronze Container**: Raw CSV files from source systems
- **Silver Container**: Cleaned and validated data (Parquet)
- **Gold Container**: Business-ready aggregated data (Delta)

### 2. **Azure Data Factory**
- Orchestrates the entire pipeline
- Schedules daily ingestion
- Triggers Databricks jobs
- Monitors pipeline health

### 3. **Azure Databricks**
- Transforms raw data (Bronze → Silver → Gold)
- Data quality checks
- Business logic implementation

### 4. **Azure Synapse Analytics**
- Serverless SQL pools for ad-hoc queries
- Integration with Power BI
- Data warehouse for reporting

### 5. **Azure Active Directory Groups**
- **data-engineers**: Full access to all resources
- **data-analysts**: Read access to Gold layer and Synapse
- **data-platform-admins**: Infrastructure management

## Technology Stack

- **IaC**: Terraform
- **CI/CD**: GitHub Actions
- **Cloud**: Azure
- **Languages**: Python, SQL, HCL

## Project Structure

```
.
├── README.md
├── terraform/
│   ├── main.tf                  # Main Terraform configuration
│   ├── variables.tf             # Input variables
│   ├── outputs.tf               # Output values
│   ├── aad.tf                   # AAD groups and role assignments
│   ├── storage.tf               # Storage account and containers
│   ├── databricks.tf            # Databricks workspace
│   ├── synapse.tf               # Synapse workspace
│   ├── data-factory.tf          # Data Factory and pipelines
│   └── terraform.tfvars.example # Example variables file
├── databricks/
│   ├── notebooks/
│   │   ├── bronze_to_silver.py  # Data cleaning transformation
│   │   └── silver_to_gold.py    # Business aggregations
│   └── jobs/
│       └── job-config.json      # Databricks job configuration
├── data-factory/
│   ├── pipeline.json            # ADF pipeline definition
│   └── dataset.json             # Dataset definitions
├── synapse/
│   └── sql-scripts/
│       └── create-views.sql     # SQL views for analysts
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml   # PR validation
│       └── terraform-apply.yml  # Deploy to Azure
└── docs/
    ├── INTERVIEW_QA.md          # Interview questions and answers
    └── ARCHITECTURE.md          # Detailed architecture
```

## Key Features

1. **Infrastructure as Code**: All resources defined in Terraform
2. **GitOps**: Changes deployed via GitHub Actions
3. **Security**: RBAC using AAD groups
4. **Data Medallion Architecture**: Bronze → Silver → Gold
5. **Monitoring**: Built-in Azure Monitor integration
6. **Cost Optimization**: Auto-pause for Databricks/Synapse

## Setup Instructions

### Prerequisites
- Azure subscription
- GitHub account
- Terraform installed locally
- Azure CLI installed

### Deployment Steps

1. **Clone and Configure**
   ```bash
   git clone <repo-url>
   cd malini
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Setup GitHub Secrets**
   - `AZURE_CREDENTIALS`: Service principal JSON
   - `ARM_CLIENT_ID`: Azure client ID
   - `ARM_CLIENT_SECRET`: Azure client secret
   - `ARM_SUBSCRIPTION_ID`: Azure subscription ID
   - `ARM_TENANT_ID`: Azure tenant ID

3. **Deploy Infrastructure**
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

4. **Deploy Data Pipelines**
   - Push to main branch triggers GitHub Actions
   - Databricks notebooks deployed automatically
   - Data Factory pipelines created

5. **Test the Pipeline**
   ```bash
   # Upload sample data to bronze container
   az storage blob upload \
     --account-name <storage-account> \
     --container-name bronze \
     --file sample-data.csv \
     --name transactions/2025/01/transactions.csv

   # Trigger Data Factory pipeline
   az datafactory pipeline create-run \
     --factory-name <adf-name> \
     --name customer-analytics-pipeline
   ```

## Interview Talking Points

1. **End-to-End Flow**: Explain data journey from source to consumption
2. **Security**: How AAD groups control access at each layer
3. **Automation**: GitOps approach with GitHub Actions
4. **Best Practices**: Medallion architecture, IaC, CI/CD
5. **Cost Management**: Auto-scaling and pause capabilities
6. **Monitoring**: How to track pipeline health and failures

## Next Steps

1. Add data quality checks in Databricks
2. Implement incremental processing
3. Add alerting for pipeline failures
4. Create Power BI dashboards
5. Implement data lineage tracking
