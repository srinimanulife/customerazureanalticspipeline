# Azure DevOps Interview Q&A - Customer Analytics Platform

This document contains comprehensive questions and answers based on the Customer Analytics Platform MVP. Use this to prepare for your Azure DevOps interview.

---

## Table of Contents
1. [Architecture and Design](#architecture-and-design)
2. [Azure Active Directory](#azure-active-directory)
3. [Azure Storage](#azure-storage)
4. [Azure Databricks](#azure-databricks)
5. [Azure Synapse](#azure-synapse)
6. [Azure Data Factory](#azure-data-factory)
7. [Terraform and IaC](#terraform-and-iac)
8. [GitHub Actions CI/CD](#github-actions-cicd)
9. [Security and Best Practices](#security-and-best-practices)
10. [Troubleshooting and Operations](#troubleshooting-and-operations)

---

## Architecture and Design

### Q1: Can you walk me through the end-to-end architecture of your data platform?

**Answer:**
"Absolutely. I designed and implemented a complete customer analytics data platform on Azure that follows the Medallion architecture pattern - Bronze, Silver, and Gold layers.

**Data Flow:**
1. **Ingestion**: Raw CSV transaction data lands in Azure Storage Bronze container
2. **Orchestration**: Azure Data Factory orchestrates the entire pipeline on a daily schedule
3. **Transformation**:
   - Databricks reads from Bronze, cleanses and validates data, writes to Silver (Parquet)
   - Another Databricks job reads Silver, applies business logic, creates aggregations, and writes to Gold (Delta)
4. **Consumption**: Azure Synapse provides SQL access to Gold layer for analysts and BI tools

**Key Components:**
- **Azure Storage**: Data Lake Gen2 with hierarchical namespace for Bronze/Silver/Gold
- **Azure Data Factory**: Orchestration with linked services and scheduled triggers
- **Azure Databricks**: Spark-based data processing with auto-scaling clusters
- **Azure Synapse**: Serverless SQL pools for analytics
- **AAD Groups**: Role-based access control for engineers, analysts, and admins

Everything is provisioned via Terraform and deployed through GitHub Actions CI/CD pipelines."

---

### Q2: Why did you choose the Medallion architecture?

**Answer:**
"I chose the Medallion architecture (Bronze-Silver-Gold) for several reasons:

**Bronze Layer (Raw):**
- Preserves raw data exactly as ingested
- Enables data replay if transformations need to change
- Supports audit and compliance requirements

**Silver Layer (Cleaned):**
- Standardized, validated, and deduplicated data
- Parquet format for efficient storage and query performance
- Partitioned by date for faster access

**Gold Layer (Business-Ready):**
- Pre-aggregated business metrics
- Delta format for ACID transactions and time travel
- Optimized for analyst queries and BI tools

This architecture provides:
- Clear separation of concerns
- Better data quality at each stage
- Flexibility to reprocess data
- Performance optimization at consumption layer
- Easy troubleshooting - can verify data at each layer"

---

## Azure Active Directory

### Q3: How did you implement role-based access control using Azure AD?

**Answer:**
"I implemented RBAC using Azure AD groups with principle of least privilege:

**Three AAD Groups:**

1. **data-engineers** (Full Access)
   - Storage Blob Data Contributor on all containers
   - Data Factory Contributor
   - Databricks Contributor
   - Synapse Administrator
   - Key Vault Secrets User

2. **data-analysts** (Read-Only Access)
   - Storage Blob Data Reader on Gold container ONLY
   - Data Factory Reader (view pipelines)
   - Synapse SQL User (query access)
   - Cannot access Bronze/Silver or modify pipelines

3. **data-platform-admins** (Infrastructure)
   - Owner role on resource group
   - Key Vault Administrator
   - Can manage all infrastructure

**Implementation in Terraform:**
```hcl
resource "azuread_group" "data_engineers" {
  display_name     = "customer-analytics-data-engineers"
  security_enabled = true
}

resource "azurerm_role_assignment" "engineers_storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_group.data_engineers.object_id
}
```

This ensures proper security boundaries and audit trails."

---

### Q4: How do you manage service principals and their credentials?

**Answer:**
"I use a combination of Azure Managed Identities and Service Principals:

**Managed Identities (Preferred):**
- Data Factory uses system-assigned managed identity
- Synapse uses system-assigned managed identity
- No credential management needed
- Automatically rotated by Azure

**Service Principal (for Databricks):**
- Created via Terraform for Databricks workspace
- Credentials stored in Azure Key Vault
- Accessed by Databricks using secret scope

**In Terraform:**
```hcl
# Create service principal
resource "azuread_application" "databricks_sp" {
  display_name = "customer-analytics-databricks-sp"
}

# Store secret in Key Vault
resource "azurerm_key_vault_secret" "databricks_sp_client_secret" {
  name         = "databricks-sp-client-secret"
  value        = azuread_service_principal_password.databricks_sp.value
  key_vault_id = azurerm_key_vault.main.id
}
```

**Best Practices:**
- Never store credentials in code or config files
- Use RBAC on Key Vault to control who can read secrets
- Regularly rotate service principal secrets
- Monitor service principal usage with Azure Monitor"

---

## Azure Storage

### Q5: Explain your Azure Storage account configuration.

**Answer:**
"I configured Azure Data Lake Storage Gen2 with these key features:

**Configuration:**
- **Account Kind**: StorageV2
- **Hierarchical Namespace**: Enabled (for ADLS Gen2)
- **Replication**: LRS for dev, GRS/GZRS for production
- **TLS**: Minimum version 1.2
- **Public Access**: Disabled

**Container Structure:**
```
storage-account/
├── bronze/          # Raw CSV files
│   ├── transactions/
│   └── customers/
├── silver/          # Cleansed Parquet
│   └── transactions/
├── gold/            # Business-ready Delta
│   ├── daily_sales_summary/
│   ├── customer_segmentation/
│   └── product_category_performance/
└── scripts/         # Pipeline scripts
```

**Terraform Code:**
```hcl
resource "azurerm_storage_account" "main" {
  name                     = "customersadev123456"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true  # Key for Data Lake Gen2

  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
}
```

**Benefits:**
- Hierarchical namespace enables better performance for big data
- POSIX-compliant ACLs for granular access control
- Supports parallel operations better than blob storage"

---

### Q6: How do you handle data lifecycle management?

**Answer:**
"I implement lifecycle management policies to optimize costs:

**Strategy:**
- **Bronze Layer**: Keep for 90 days, then move to Cool tier, archive after 1 year
- **Silver Layer**: Keep for 180 days, then move to Cool tier
- **Gold Layer**: Keep in Hot tier (frequently accessed by analysts)

**Azure Storage Lifecycle Policy (would add in Terraform):**
```hcl
resource "azurerm_storage_management_policy" "lifecycle" {
  storage_account_id = azurerm_storage_account.main.id

  rule {
    name    = "bronze-lifecycle"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["bronze/"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days    = 90
        tier_to_archive_after_days = 365
        delete_after_days          = 730
      }
    }
  }
}
```

**Benefits:**
- Reduces storage costs significantly
- Automatic tier transitions
- Compliance with data retention policies"

---

## Azure Databricks

### Q7: Walk me through your Databricks implementation.

**Answer:**
"I implemented Databricks as the core data transformation engine:

**Workspace Configuration:**
- **SKU**: Premium (for RBAC and enhanced security)
- **Networking**: Public access for dev, private endpoints for production
- **Cluster**: Auto-scaling (1-4 workers) with auto-termination after 20 minutes

**Two Main Notebooks:**

1. **bronze_to_silver.py**:
   - Reads CSV from Bronze
   - Schema validation
   - Data quality checks (nulls, duplicates, invalid values)
   - Type conversions
   - Writes Parquet to Silver partitioned by date

2. **silver_to_gold.py**:
   - Reads Parquet from Silver
   - Business aggregations:
     - Daily sales summary
     - Customer segmentation (HIGH/MEDIUM/LOW value)
     - Product category performance
     - Store location analysis
   - Writes Delta tables to Gold

**Terraform Configuration:**
```hcl
resource "databricks_cluster" "shared_autoscaling" {
  cluster_name            = "Shared Autoscaling Cluster"
  spark_version           = "13.3.x-scala2.12"
  node_type_id            = "Standard_DS3_v2"
  autotermination_minutes = 20

  autoscale {
    min_workers = 1
    max_workers = 4
  }
}
```

**Key Features:**
- Secret scope linked to Azure Key Vault for credentials
- Notebook parameters for dynamic execution
- Returns status to Data Factory for pipeline monitoring"

---

### Q8: How do you ensure data quality in Databricks?

**Answer:**
"I implement multiple layers of data quality checks:

**1. Schema Validation:**
```python
# Define explicit schema
transaction_schema = StructType([
    StructField("transaction_id", StringType(), False),  # Not nullable
    StructField("customer_id", StringType(), False),
    StructField("amount", StringType(), False),
    # ...
])
```

**2. Data Validation:**
```python
silver_df = bronze_df \
    .filter(col("transaction_id").isNotNull()) \
    .filter(col("customer_id").isNotNull()) \
    .filter(col("amount") > 0) \
    .filter(col("quantity") > 0) \
    .dropDuplicates(["transaction_id"])
```

**3. Quality Metrics:**
```python
total_bronze_records = bronze_df.count()
total_silver_records = silver_df.count()
rejected_records = total_bronze_records - total_silver_records
quality_rate = (total_silver_records / total_bronze_records * 100)
```

**4. Quality Flag:**
```python
silver_df = silver_df.withColumn("is_valid",
    when((col("amount").isNotNull()) &
         (col("transaction_date").isNotNull()), True)
    .otherwise(False))
```

**Monitoring:**
- Track rejection rates
- Alert if quality rate drops below threshold
- Store quality metrics for trending
- Quarantine bad records for investigation"

---

## Azure Synapse

### Q9: Explain your Synapse Analytics setup.

**Answer:**
"I configured Synapse Analytics for SQL-based analytics:

**Components:**

1. **Synapse Workspace:**
   - System-assigned managed identity for storage access
   - AAD admin group configured
   - Firewall rules for Azure services

2. **Serverless SQL Pools:**
   - No provisioning required
   - Pay per query
   - Perfect for ad-hoc analysis

3. **Spark Pool:**
   - Auto-scale (3-5 nodes)
   - Auto-pause after 15 minutes
   - For big data processing if needed

**External Tables Configuration:**
```sql
-- Create external data source pointing to Gold layer
CREATE EXTERNAL DATA SOURCE GoldStorage
WITH (
    LOCATION = 'abfss://gold@customersadev.dfs.core.windows.net',
    CREDENTIAL = StorageCredential  -- Uses managed identity
);

-- Create external table for Delta data
CREATE EXTERNAL TABLE gold.daily_sales_summary
(
    transaction_date DATE,
    total_revenue DECIMAL(18,2),
    -- ...
)
WITH (
    LOCATION = 'daily_sales_summary',
    DATA_SOURCE = GoldStorage,
    FILE_FORMAT = DeltaFormat
);
```

**Views for Analysts:**
- `vw_top_categories_last_30_days`
- `vw_high_value_customers`
- `vw_monthly_revenue_trend`
- `vw_store_comparison`

**Terraform:**
```hcl
resource "azurerm_synapse_workspace" "main" {
  name                = "customer-analytics-synapse"
  sql_administrator_login = "sqladmin"

  aad_admin {
    login     = azuread_group.admins.display_name
    object_id = azuread_group.admins.object_id
  }

  identity {
    type = "SystemAssigned"
  }
}
```"

---

### Q10: How do you connect Synapse to Power BI?

**Answer:**
"I set up Synapse integration with Power BI for business users:

**Connection Methods:**

1. **Serverless SQL Endpoint:**
   - Get SQL endpoint: `customer-analytics-synapse.sql.azuresynapse.net`
   - Database: `CustomerAnalytics`
   - Authentication: AAD (pass-through for user identity)

2. **Power BI Setup:**
```
Data Source: SQL Server
Server: customer-analytics-synapse.sql.azuresynapse.net
Database: CustomerAnalytics
Data Connectivity: DirectQuery or Import
Authentication: Azure Active Directory
```

3. **Views for BI:**
   - Create business-friendly views in Synapse
   - Hide complexity of Delta tables
   - Pre-aggregate where possible for performance

**Example BI View:**
```sql
CREATE VIEW gold.vw_executive_dashboard AS
SELECT
    YEAR(transaction_date) as Year,
    MONTH(transaction_date) as Month,
    SUM(total_revenue) as Revenue,
    SUM(total_transactions) as Transactions,
    SUM(unique_customers) as Customers
FROM gold.daily_sales_summary
GROUP BY YEAR(transaction_date), MONTH(transaction_date);
```

**Benefits:**
- Analysts access data through familiar SQL interface
- Row-level security possible through AAD integration
- No data duplication
- Real-time or near-real-time dashboards"

---

## Azure Data Factory

### Q11: Describe your Data Factory pipeline implementation.

**Answer:**
"I built an orchestration pipeline in Data Factory that coordinates the entire data flow:

**Pipeline: CustomerAnalyticsPipeline**

**Activities:**

1. **CheckNewFiles** (Get Metadata)
   - Checks if new files exist in Bronze container
   - Gets file metadata (exists, lastModified)
   - Fails gracefully if no new data

2. **TransformBronzeToSilver** (Databricks Notebook)
   - Depends on: CheckNewFiles (Succeeded)
   - Executes: `/Shared/pipelines/bronze_to_silver`
   - Parameters passed:
     ```json
     {
       "storage_account": "customersadev123456",
       "source_container": "bronze",
       "target_container": "silver"
     }
     ```
   - Retry: 1 time
   - Timeout: 12 hours

3. **TransformSilverToGold** (Databricks Notebook)
   - Depends on: TransformBronzeToSilver (Succeeded)
   - Executes: `/Shared/pipelines/silver_to_gold`
   - Creates multiple gold tables

**Terraform Configuration:**
```hcl
resource "azurerm_data_factory_pipeline" "main" {
  name            = "CustomerAnalyticsPipeline"
  data_factory_id = azurerm_data_factory.main.id

  activities_json = jsonencode([
    {
      name = "TransformBronzeToSilver"
      type = "DatabricksNotebook"
      typeProperties = {
        notebookPath = "/Shared/pipelines/bronze_to_silver"
        baseParameters = {
          storage_account = azurerm_storage_account.main.name
        }
      }
    }
  ])
}
```

**Trigger:**
- Daily schedule at 2 AM
- Can also be triggered manually or via API
- Initially disabled for testing

**Linked Services:**
- Azure Blob Storage (managed identity)
- Databricks (MSI workspace resource ID)
- Key Vault (for secrets)"

---

### Q12: How do you handle pipeline failures and monitoring?

**Answer:**
"I implement comprehensive monitoring and error handling:

**Error Handling:**

1. **Retry Logic:**
   - Each activity configured with retry count (usually 1-2)
   - Exponential backoff between retries

2. **Dependency Conditions:**
   - Activities only run if dependencies succeeded
   - Can configure to run on failure for cleanup

3. **Notebook Error Handling:**
```python
try:
    # Data processing logic
    silver_df.write.parquet(silver_path)
    dbutils.notebook.exit("SUCCESS")
except Exception as e:
    print(f"Error: {str(e)}")
    dbutils.notebook.exit(f"FAILED: {str(e)}")
    raise
```

**Monitoring:**

1. **Azure Monitor:**
   - Pipeline run status
   - Activity duration metrics
   - Failed runs alerts

2. **Alerts Configuration:**
```hcl
resource "azurerm_monitor_metric_alert" "adf_failed_runs" {
  name                = "adf-failed-pipeline-runs"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_data_factory.main.id]

  criteria {
    metric_name      = "PipelineFailedRuns"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops_team.id
  }
}
```

3. **Logging:**
   - All pipeline runs logged to Azure Monitor Logs
   - Databricks logs to DBFS
   - Can query with Kusto (KQL)

**Incident Response:**
1. Alert fires to ops team
2. Check pipeline run history in ADF
3. Review Databricks notebook output
4. Check data quality metrics
5. Fix issue and rerun pipeline"

---

## Terraform and IaC

### Q13: Walk me through your Terraform structure and best practices.

**Answer:**
"I organized Terraform code following best practices for maintainability:

**Project Structure:**
```
terraform/
├── main.tf              # Provider config, resource group, random suffix
├── variables.tf         # All input variables with descriptions
├── outputs.tf           # Output values for other tools
├── aad.tf              # AAD groups and role assignments
├── keyvault.tf         # Key Vault and secrets
├── storage.tf          # Storage account and containers
├── databricks.tf       # Databricks workspace and clusters
├── synapse.tf          # Synapse workspace and pools
├── data-factory.tf     # ADF pipelines and linked services
└── terraform.tfvars    # Variable values (gitignored)
```

**Key Practices:**

1. **Modular Organization:**
   - Each Azure service in separate file
   - Easy to navigate and maintain
   - Clear ownership boundaries

2. **Variables with Validation:**
```hcl
variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

3. **Remote State Management:**
```hcl
backend "azurerm" {
  resource_group_name  = "tfstate-rg"
  storage_account_name = "tfstate123456"
  container_name       = "tfstate"
  key                  = "terraform.tfstate"
}
```

4. **Resource Naming Convention:**
```hcl
locals {
  resource_suffix = "${var.environment}-${random_string.suffix.result}"
}

resource "azurerm_storage_account" "main" {
  name = "${var.project_name}sa${local.resource_suffix}"
}
```

5. **Tags for Organization:**
```hcl
locals {
  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project_name
    }
  )
}
```

6. **Sensitive Data:**
   - Marked as `sensitive = true`
   - Never in code
   - Passed via environment variables or CI/CD secrets"

---

### Q14: How do you manage Terraform state and prevent conflicts?

**Answer:**
"State management is critical for team collaboration:

**Remote State Backend:**
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatedevops123"
    container_name       = "tfstate"
    key                  = "customer-analytics.tfstate"
  }
}
```

**State Locking:**
- Azure Storage automatically provides state locking
- Prevents concurrent modifications
- Uses lease mechanism on blob storage

**Best Practices:**

1. **Never Commit State Files:**
```gitignore
# .gitignore
*.tfstate
*.tfstate.backup
.terraform/
```

2. **State Backup:**
   - Azure Storage provides versioning
   - Can recover previous state versions
   - Enable soft delete for 30-day recovery

3. **Workspace Separation:**
```bash
# Different environments
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod
```

4. **State Commands:**
```bash
# View state
terraform state list

# Remove resource from state
terraform state rm azurerm_resource_group.main

# Import existing resource
terraform import azurerm_resource_group.main /subscriptions/.../resourceGroups/my-rg

# Refresh state
terraform refresh
```

5. **Team Workflow:**
   - Always run `terraform plan` before apply
   - Review plan output carefully
   - Use pull requests for changes
   - Automated plan on PR, apply on merge

**CI/CD Integration:**
```yaml
# GitHub Actions ensures only one apply runs at a time
jobs:
  terraform-apply:
    runs-on: ubuntu-latest
    environment: production  # Requires manual approval
```"

---

### Q15: How do you handle Terraform secrets?

**Answer:**
"I never store secrets in Terraform code:

**Methods:**

1. **Environment Variables:**
```bash
export TF_VAR_synapse_sql_admin_password="SecurePassword123!"
terraform apply
```

2. **CI/CD Secrets:**
```yaml
# GitHub Actions
- name: Terraform Apply
  run: terraform apply
  env:
    TF_VAR_synapse_sql_admin_password: ${{ secrets.SYNAPSE_PASSWORD }}
```

3. **Variable Files (Not Committed):**
```hcl
# terraform.tfvars (in .gitignore)
synapse_sql_admin_password = "SecurePassword123!"
```

4. **Azure Key Vault Data Source:**
```hcl
data "azurerm_key_vault_secret" "admin_password" {
  name         = "synapse-admin-password"
  key_vault_id = data.azurerm_key_vault.existing.id
}

resource "azurerm_synapse_workspace" "main" {
  sql_administrator_login_password = data.azurerm_key_vault_secret.admin_password.value
}
```

5. **Terraform Cloud Variables:**
   - Mark as sensitive in TF Cloud
   - Encrypted at rest
   - Not visible in logs

**Sensitive Variable Declaration:**
```hcl
variable "synapse_sql_admin_password" {
  description = "Synapse SQL admin password"
  type        = string
  sensitive   = true  # Redacts from output
}
```

**What NOT to Do:**
```hcl
# ❌ NEVER DO THIS
variable "password" {
  default = "password123"  # Terrible!
}
```"

---

## GitHub Actions CI/CD

### Q16: Explain your CI/CD workflow with GitHub Actions.

**Answer:**
"I implemented GitOps with GitHub Actions for automated deployments:

**Three Workflows:**

### 1. **Terraform Plan** (PR Validation)
- Triggers: Pull requests to main, changes in terraform/
- Steps:
  1. Checkout code
  2. Setup Terraform
  3. Azure login via OIDC
  4. `terraform fmt -check` (enforce formatting)
  5. `terraform init`
  6. `terraform validate`
  7. `terraform plan`
  8. Comment plan output on PR

```yaml
name: Terraform Plan
on:
  pull_request:
    branches: [main]
    paths: ['terraform/**']

jobs:
  terraform-plan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - name: Terraform Plan
        run: terraform plan -no-color
```

### 2. **Terraform Apply** (Deployment)
- Triggers: Push to main, changes in terraform/
- Requires: Manual approval (production environment)
- Steps:
  1. Checkout code
  2. Setup Terraform
  3. Azure login
  4. `terraform init`
  5. `terraform plan`
  6. `terraform apply -auto-approve`
  7. Upload outputs as artifacts

```yaml
name: Terraform Apply
on:
  push:
    branches: [main]
    paths: ['terraform/**']

jobs:
  terraform-apply:
    runs-on: ubuntu-latest
    environment: production  # Requires approval
```

### 3. **Deploy Databricks** (Notebook Deployment)
- Triggers: Push to main, changes in databricks/
- Steps:
  1. Install Databricks CLI
  2. Configure authentication
  3. Upload notebooks to workspace

```yaml
- name: Deploy Notebook
  run: |
    databricks workspace import \
      --language PYTHON \
      --overwrite \
      databricks/notebooks/bronze_to_silver.py \
      /Shared/pipelines/bronze_to_silver
```

**Secrets Configuration:**
```
Required GitHub Secrets:
- ARM_CLIENT_ID
- ARM_CLIENT_SECRET
- ARM_SUBSCRIPTION_ID
- ARM_TENANT_ID
- SYNAPSE_SQL_ADMIN_PASSWORD
- DATABRICKS_HOST
- DATABRICKS_TOKEN
```

**Benefits:**
- Automated testing on every PR
- Manual approval gate for production
- Audit trail of all changes
- Rollback capability via Git
- Consistent deployments"

---

### Q17: How do you implement approval gates and environment protection?

**Answer:**
"I use GitHub Environments for deployment protection:

**Environment Configuration:**

1. **Create Production Environment:**
   - Go to Repository Settings → Environments
   - Create 'production' environment
   - Configure protection rules

2. **Protection Rules:**
```yaml
Environment: production
  ✓ Required reviewers: 2 approvers
  ✓ Wait timer: 5 minutes
  ✓ Deployment branches: main only
  ✓ Environment secrets: Production credentials
```

3. **Workflow Configuration:**
```yaml
jobs:
  terraform-apply:
    runs-on: ubuntu-latest
    environment: production  # Triggers approval requirement
    steps:
      - name: Terraform Apply
        run: terraform apply -auto-approve
```

**Approval Process:**
1. Developer creates PR with infrastructure changes
2. Terraform Plan runs automatically, comments on PR
3. Team reviews plan output
4. PR merged to main
5. **Approval request sent to designated reviewers**
6. Reviewer approves in GitHub UI
7. Terraform Apply executes
8. Notification sent on completion

**Multiple Environments:**
```yaml
jobs:
  deploy-dev:
    environment: development  # Auto-deploy, no approval

  deploy-staging:
    needs: deploy-dev
    environment: staging  # 1 approver required

  deploy-prod:
    needs: deploy-staging
    environment: production  # 2 approvers required
```

**Benefits:**
- Prevents accidental production deployments
- Ensures peer review
- Provides audit trail
- Configurable per environment
- Can require specific reviewers (e.g., only lead engineers)"

---

### Q18: How do you handle deployment rollbacks?

**Answer:**
"I have multiple rollback strategies:

**1. Git Revert (Preferred):**
```bash
# Identify bad commit
git log

# Revert the commit
git revert abc123

# Push to main
git push origin main

# GitHub Actions automatically applies reverted state
```

**2. Terraform State Rollback:**
```bash
# List state versions in Azure Storage
az storage blob list \
  --account-name tfstatedevops \
  --container-name tfstate

# Download previous state
az storage blob download \
  --account-name tfstatedevops \
  --container-name tfstate \
  --name terraform.tfstate \
  --version-id <previous-version> \
  --file terraform.tfstate.backup

# Restore (with extreme caution)
# Better to revert code and reapply
```

**3. Terraform Destroy Specific Resource:**
```bash
# Remove problematic resource
terraform destroy -target=azurerm_databricks_workspace.main

# Reapply with fix
terraform apply
```

**4. Azure Resource Recovery:**
```bash
# Some Azure resources support soft delete
az synapse workspace recover \
  --name customer-analytics-synapse \
  --resource-group customer-analytics-rg
```

**Best Practices:**

1. **Always test in dev first:**
```yaml
jobs:
  deploy-dev:
    environment: development
    # Test here first

  deploy-prod:
    needs: deploy-dev  # Only after dev succeeds
    environment: production
```

2. **Terraform Plan Review:**
   - Carefully review plan output
   - Look for unexpected deletions
   - Verify resource replacements

3. **Backup Before Major Changes:**
```bash
# Export current state
terraform show > current-state.txt

# Backup data if needed
az storage blob sync ...
```

4. **Incremental Changes:**
   - Small, focused changes
   - Easier to rollback
   - Less risk

**Incident Response:**
```bash
# Quick rollback procedure:
1. Identify last good commit: git log
2. Revert changes: git revert <commit>
3. Push to trigger deployment: git push
4. Monitor deployment: Check GitHub Actions
5. Verify in Azure Portal
6. Test critical paths
```"

---

## Security and Best Practices

### Q19: What security measures did you implement?

**Answer:**
"I implemented security at multiple layers:

**1. Network Security:**
- Private endpoints for production (disabled for dev)
- Storage firewall rules
- NSGs for Databricks virtual network
- Synapse firewall whitelist

**2. Identity and Access:**
- Azure AD authentication everywhere
- No SQL authentication
- RBAC with least privilege
- Service principals with minimal permissions
- Managed identities preferred over service principals

**3. Data Encryption:**
```hcl
resource "azurerm_storage_account" "main" {
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"

  # Encryption at rest (enabled by default)
  # Data encrypted with Microsoft-managed keys
}
```

**4. Secrets Management:**
- All secrets in Azure Key Vault
- RBAC on Key Vault
- Soft delete enabled
- Purge protection for production
- Audit logging enabled

```hcl
resource "azurerm_key_vault" "main" {
  enable_rbac_authorization = true
  soft_delete_retention_days = 90
  purge_protection_enabled  = true  # Production
}
```

**5. Monitoring and Auditing:**
```hcl
# Diagnostic settings for all resources
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name               = "storage-diagnostics"
  target_resource_id = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
}
```

**6. Data Protection:**
- Soft delete for blobs (7-30 days)
- Versioning enabled
- Container-level access, never public
- Row-level security in Synapse (if needed)

**7. Compliance:**
- Tags for cost tracking
- Resource locks for critical resources
- Backup strategies
- Data retention policies

**8. CI/CD Security:**
- Secrets in GitHub Secrets (encrypted)
- OIDC authentication (no long-lived credentials)
- Required reviewers for production
- Branch protection rules

**9. Databricks Security:**
```hcl
resource "databricks_secret_scope" "kv_backed" {
  name = "azure-key-vault-secrets"

  keyvault_metadata {
    resource_id = azurerm_key_vault.main.id
    dns_name    = azurerm_key_vault.main.vault_uri
  }
}
```

**10. Regular Reviews:**
- Azure Security Center recommendations
- Access reviews for AAD groups
- Unused resource cleanup
- Cost anomaly detection"

---

### Q20: How do you handle cost optimization?

**Answer:**
"Cost optimization is built into the architecture:

**1. Auto-Scaling and Auto-Pause:**

**Databricks:**
```hcl
autoscale {
  min_workers = 1
  max_workers = 4
}
autotermination_minutes = 20
```

**Synapse Spark Pool:**
```hcl
auto_pause {
  delay_in_minutes = 15
}
auto_scale {
  max_node_count = 5
  min_node_count = 3
}
```

**2. Right-Sizing:**
- Use Standard_DS3_v2 for Databricks (cost-effective)
- Serverless SQL in Synapse (pay-per-query)
- No dedicated SQL pool in dev (commented out in code)

**3. Storage Tiers:**
- Hot tier for Gold layer (frequent access)
- Cool tier for Silver after 90 days
- Archive for Bronze after 1 year
- Lifecycle policies automated

**4. Reserved Capacity:**
```
Production recommendations:
- Azure Reserved VMs (1-3 year commitment)
- Databricks Commit Units
- Synapse reserved capacity
- Can save 30-70%
```

**5. Resource Tags:**
```hcl
tags = {
  CostCenter  = "Analytics"
  Environment = "dev"
  Project     = "CustomerAnalytics"
}
```

**6. Monitoring:**
```hcl
resource "azurerm_monitor_action_group" "cost_alerts" {
  name = "cost-alert-action-group"

  email_receiver {
    name          = "cost-team"
    email_address = "costs@company.com"
  }
}

resource "azurerm_consumption_budget" "monthly" {
  name              = "monthly-budget"
  resource_group_id = azurerm_resource_group.main.id
  amount            = 5000
  time_period {
    start_date = "2025-01-01"
  }
  notification {
    threshold = 80
    operator  = "GreaterThan"
    contact_groups = [azurerm_monitor_action_group.cost_alerts.id]
  }
}
```

**7. Cost Optimization Practices:**
- Shut down dev environments outside business hours
- Delete unused resources
- Use spot instances where possible
- Optimize data formats (Parquet, Delta)
- Partition data properly
- Incremental processing vs full refresh

**Cost Breakdown Estimate (Dev):**
```
Monthly estimate:
- Storage (1TB, Hot): ~$20
- Databricks (100 DBU/month): ~$150
- Synapse (100 queries/day): ~$50
- Data Factory (100 runs/month): ~$10
- Networking: ~$20
Total: ~$250/month
```"

---

## Troubleshooting and Operations

### Q21: How would you troubleshoot a failed pipeline?

**Answer:**
"I follow a systematic troubleshooting approach:

**Step 1: Identify the Failure**
```
- Check Azure Data Factory UI
- Look at pipeline run history
- Identify which activity failed
- Check error message
```

**Step 2: Review Logs**

**Data Factory:**
```
1. Go to Monitor tab in ADF
2. Click on failed pipeline run
3. Check activity output
4. Review error details
```

**Databricks:**
```python
# Notebook has detailed logging
print(f"Processing file: {file_path}")
print(f"Records read: {df.count()}")

# Errors are captured
try:
    process_data()
except Exception as e:
    print(f"Error: {str(e)}")
    raise
```

**Azure Monitor:**
```kusto
// Query ADF logs
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DATAFACTORY"
| where Status == "Failed"
| order by TimeGenerated desc
| take 10
```

**Step 3: Common Issues and Solutions**

**Issue 1: Authentication Failure**
```
Error: "Failed to authenticate with storage"

Solution:
- Check managed identity has proper role
- Verify storage firewall rules
- Check Key Vault access policies
- Validate service principal credentials
```

**Issue 2: File Not Found**
```
Error: "Path not found: abfss://bronze@..."

Solution:
- Verify file uploaded to correct container
- Check path parameters passed to notebook
- Validate storage account name
- Check hierarchical namespace enabled
```

**Issue 3: Databricks Cluster Issues**
```
Error: "Cluster failed to start"

Solution:
- Check cluster configuration
- Verify subnet has capacity
- Review Azure quotas
- Check network security groups
```

**Issue 4: Data Quality Failures**
```
Error: "0 records written to silver"

Solution:
- Check bronze data quality
- Review validation rules (too strict?)
- Examine rejected records
- Validate schema matches expectations
```

**Step 4: Fix and Rerun**
```bash
# Fix the issue in code
git commit -m "fix: Handle null values in amount field"
git push

# Or rerun pipeline manually
az datafactory pipeline create-run \
  --factory-name customer-analytics-adf \
  --name CustomerAnalyticsPipeline
```

**Step 5: Post-Mortem**
```
1. Document what failed
2. Root cause analysis
3. Implement preventive measures
4. Update monitoring/alerts
5. Add data quality checks if needed
```

**Proactive Monitoring:**
```hcl
# Alert on failures
resource "azurerm_monitor_metric_alert" "adf_failed_runs" {
  name = "adf-pipeline-failures"

  criteria {
    metric_name = "PipelineFailedRuns"
    aggregation = "Total"
    operator    = "GreaterThan"
    threshold   = 0
  }

  action {
    # Send to PagerDuty/Slack/Email
  }
}
```"

---

### Q22: What metrics do you monitor in production?

**Answer:**
"I monitor metrics across all platform components:

**1. Data Factory Metrics:**
- Pipeline run success rate
- Pipeline duration
- Activity failures
- Trigger success rate

**Kusto Query:**
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DATAFACTORY"
| summarize
    TotalRuns = count(),
    Failed = countif(Status == "Failed"),
    SuccessRate = (1.0 - (countif(Status == "Failed") * 1.0 / count())) * 100
  by bin(TimeGenerated, 1d)
```

**2. Databricks Metrics:**
- Job success rate
- Execution time
- Cluster utilization
- DBU consumption
- Data quality metrics (rejection rates)

**3. Storage Metrics:**
- Blob transaction count
- Ingress/egress
- Latency
- Throttling errors

**4. Synapse Metrics:**
- Query duration
- Query failures
- Active queries
- Data processed

**5. Cost Metrics:**
- Daily/monthly spend by service
- DBU consumption
- Storage costs
- Unexpected spikes

**6. Data Quality Metrics:**
```python
# Tracked in each pipeline run
metrics = {
    "total_records_processed": 10000,
    "valid_records": 9950,
    "rejected_records": 50,
    "data_quality_rate": 99.5,
    "execution_time_seconds": 120
}
```

**Dashboard Configuration:**
```
Azure Dashboard with:
- Pipeline run status (last 24h)
- Data quality trend (last 7 days)
- Cost trend (last 30 days)
- Storage growth
- Error rate by component
```

**Alerts:**
```
Critical:
- Pipeline failure
- Data quality < 95%
- Cost spike > 150% of baseline

Warning:
- Pipeline duration > 2x normal
- Storage approaching limit
- Databricks cluster auto-termination failures
```

**Log Analytics Workspace:**
```hcl
resource "azurerm_log_analytics_workspace" "main" {
  name                = "customer-analytics-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Send all diagnostics here
resource "azurerm_monitor_diagnostic_setting" "adf" {
  name                       = "adf-diagnostics"
  target_resource_id         = azurerm_data_factory.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "PipelineRuns"
  }

  metric {
    category = "AllMetrics"
  }
}
```"

---

### Q23: How do you ensure data lineage and auditability?

**Answer:**
"Data lineage and auditability are critical for compliance:

**1. Timestamp Tracking:**
```python
# Add metadata columns at each stage
silver_df = bronze_df \
    .withColumn("ingestion_timestamp", current_timestamp()) \
    .withColumn("source_file", input_file_name()) \
    .withColumn("pipeline_run_id", lit(pipeline_run_id))

gold_df = silver_df \
    .withColumn("load_timestamp", current_timestamp()) \
    .withColumn("transformation_version", lit("v1.2"))
```

**2. Partition by Date:**
```python
# Easy to trace when data was processed
silver_df.write \
    .partitionBy("ingestion_date") \
    .parquet(silver_path)
```

**3. Delta Lake Time Travel:**
```python
# Can query historical versions
df = spark.read \
    .format("delta") \
    .option("versionAsOf", 5) \
    .load(gold_path)

# Or by timestamp
df = spark.read \
    .format("delta") \
    .option("timestampAsOf", "2025-01-15") \
    .load(gold_path)

# View history
spark.sql("DESCRIBE HISTORY delta.`/path/to/gold/table`")
```

**4. Pipeline Metadata:**
```json
// Data Factory passes metadata
{
  "pipeline_name": "CustomerAnalyticsPipeline",
  "run_id": "abc-123-def",
  "trigger_type": "ScheduleTrigger",
  "trigger_time": "2025-01-19T02:00:00Z"
}
```

**5. Audit Logs:**
```kusto
// Who accessed what data
AzureDiagnostics
| where ResourceType == "STORAGEACCOUNTS"
| where Category == "StorageRead"
| project TimeGenerated, CallerIdentity, ObjectKey, StatusCode
| where CallerIdentity contains "user@company.com"
```

**6. Data Catalog:**
```hcl
# Azure Purview for data catalog (if available)
resource "azurerm_purview_account" "main" {
  name                = "customer-analytics-purview"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  identity {
    type = "SystemAssigned"
  }
}

# Automatically scans and catalogs data
# Provides:
# - Data lineage visualization
# - Column-level lineage
# - Sensitivity classifications
# - Search and discovery
```

**7. Documentation in Code:**
```python
# Databricks notebook
# MAGIC %md
# MAGIC # Data Lineage
# MAGIC
# MAGIC **Source**: Bronze container, /transactions/*.csv
# MAGIC **Target**: Silver container, /transactions (partitioned by date)
# MAGIC **Transformations**:
# MAGIC - Remove nulls in transaction_id, customer_id
# MAGIC - Convert amount to decimal
# MAGIC - Standardize category names
# MAGIC **Data Quality**: Rejection rate tracked
```

**8. Immutable Audit Trail:**
- All pipeline runs logged
- Git history shows code changes
- Azure AD logs show access
- Storage logs show who read/wrote data
- Cannot be modified retroactively

**Compliance Benefits:**
- GDPR: Can show what happened to user data
- SOX: Financial data processing is auditable
- HIPAA: Healthcare data access tracked
- General: Complete data lineage for investigations"

---

## Advanced Scenarios

### Q24: How would you implement incremental data processing?

**Answer:**
"Incremental processing is crucial for performance and cost:

**Current State (Full Refresh):**
```python
# Reads all bronze data every time
bronze_df = spark.read.csv(bronze_path)
```

**Incremental Approach:**

**1. Watermark-Based Processing:**
```python
# Bronze to Silver (Incremental)
last_processed_date = spark.sql("""
    SELECT MAX(ingestion_date)
    FROM silver.transactions
""").collect()[0][0] or '1900-01-01'

bronze_df = spark.read.csv(bronze_path) \
    .filter(col("file_date") > last_processed_date)

# Only process new data
silver_df = transform(bronze_df)

# Append to silver
silver_df.write.mode("append").parquet(silver_path)
```

**2. Delta Lake Merge (Upsert):**
```python
from delta.tables import DeltaTable

# Read new data
new_data = spark.read.parquet(silver_path_new)

# Load existing Delta table
target_table = DeltaTable.forPath(spark, gold_path)

# Merge (upsert)
target_table.alias("target").merge(
    new_data.alias("source"),
    "target.transaction_id = source.transaction_id"
).whenMatchedUpdateAll() \
 .whenNotMatchedInsertAll() \
 .execute()
```

**3. Change Data Capture (CDC):**
```python
# If source supports CDC
cdc_df = spark.read \
    .format("delta") \
    .option("readChangeFeed", "true") \
    .option("startingVersion", last_version) \
    .load(bronze_path)

# Process only changes
# _change_type: insert, update, delete
```

**4. File-Based Incremental:**
```python
# Track processed files
processed_files = spark.read.table("control.processed_files")

# Get new files
all_files = dbutils.fs.ls(bronze_path)
new_files = [f for f in all_files
             if f.name not in processed_files]

# Process only new files
for file in new_files:
    df = spark.read.csv(file.path)
    process_and_write(df)

    # Mark as processed
    log_processed_file(file.name)
```

**5. Data Factory Incremental Copy:**
```json
{
  "source": {
    "type": "BlobSource",
    "recursive": true,
    "modifiedDatetimeStart": "@{activity('LookupLastRunTime').output.value}",
    "modifiedDatetimeEnd": "@{utcnow()}"
  }
}
```

**6. Databricks Autoloader:**
```python
# Automatically processes new files
df = spark.readStream \
    .format("cloudFiles") \
    .option("cloudFiles.format", "csv") \
    .option("cloudFiles.schemaLocation", checkpoint_path) \
    .load(bronze_path)

# Stream to silver
df.writeStream \
    .format("delta") \
    .option("checkpointLocation", checkpoint_path) \
    .option("mergeSchema", "true") \
    .start(silver_path)
```

**Benefits:**
- Faster processing (only new data)
- Lower costs (less compute)
- More frequent updates (can run hourly vs daily)
- Reduced resource usage

**Control Table:**
```sql
CREATE TABLE control.pipeline_watermarks (
    table_name STRING,
    last_processed_timestamp TIMESTAMP,
    last_processed_id STRING,
    updated_at TIMESTAMP
);
```"

---

### Q25: How would you scale this solution for larger data volumes?

**Answer:**
"Several strategies for scaling to TB/PB scale:

**1. Databricks Optimization:**

**Larger Clusters:**
```hcl
resource "databricks_cluster" "large" {
  node_type_id = "Standard_DS14_v2"  # Larger nodes

  autoscale {
    min_workers = 5
    max_workers = 50  # Scale out
  }

  # Enable cluster pools for faster startup
  instance_pool_id = databricks_instance_pool.main.id
}
```

**Optimize Spark Configuration:**
```python
spark.conf.set("spark.sql.shuffle.partitions", "400")
spark.conf.set("spark.sql.adaptive.enabled", "true")
spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")
```

**2. Data Partitioning:**
```python
# Partition by date and category
gold_df.write \
    .partitionBy("year", "month", "category") \
    .format("delta") \
    .save(gold_path)

# Enables partition pruning
result = spark.read \
    .format("delta") \
    .load(gold_path) \
    .where("year = 2025 AND month = 1")  # Only reads needed partitions
```

**3. Z-Ordering (Delta):**
```python
from delta.tables import DeltaTable

# Optimize layout for queries
DeltaTable.forPath(spark, gold_path) \
    .optimize() \
    .executeZOrderBy("customer_id", "transaction_date")

# Makes queries on these columns much faster
```

**4. Caching:**
```python
# Cache frequently accessed data
customer_df = spark.read.delta(customer_path)
customer_df.cache()
```

**5. Synapse Optimization:**

**Materialized Views:**
```sql
CREATE MATERIALIZED VIEW gold.mv_monthly_sales
AS
SELECT
    YEAR(transaction_date) as year,
    MONTH(transaction_date) as month,
    SUM(total_revenue) as revenue
FROM gold.daily_sales_summary
GROUP BY YEAR(transaction_date), MONTH(transaction_date);
```

**Result Set Caching:**
```sql
SET RESULT_SET_CACHING ON;
-- Subsequent same queries use cache
```

**6. Dedicated SQL Pool (for very large):**
```hcl
resource "azurerm_synapse_sql_pool" "large" {
  name                 = "largedw"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  sku_name             = "DW1000c"  # Scale up

  # Enables:
  # - Distributed storage
  # - Massively parallel processing
  # - Result set caching
}
```

**7. Streaming Architecture:**
```
For real-time requirements:

Event Hubs → Stream Analytics → Databricks Streaming → Delta Lake
                                       ↓
                                  Synapse Real-time
```

**8. Data Factory Optimization:**

**Parallel Execution:**
```json
{
  "activities": [
    {
      "name": "ProcessPartition1",
      "type": "DatabricksNotebook",
      "dependsOn": []  // Run in parallel
    },
    {
      "name": "ProcessPartition2",
      "type": "DatabricksNotebook",
      "dependsOn": []  // Run in parallel
    }
  ]
}
```

**9. Cost Considerations:**
```
For 100TB+ :
- Use Azure Reserved Capacity
- Consider Databricks Photon engine
- Implement data archival policies
- Use serverless for ad-hoc queries
- Dedicated pools for regular workloads
```

**10. Monitoring at Scale:**
```kusto
// Query performance monitoring
SynapseSqlPoolExecRequests
| where Status == "Completed"
| summarize
    P50 = percentile(TotalElapsedTime, 50),
    P95 = percentile(TotalElapsedTime, 95),
    P99 = percentile(TotalElapsedTime, 99)
  by bin(StartTime, 1h)
```

**Architecture Evolution:**
```
Small (< 1TB):  Current architecture works great
Medium (1-10TB): Add partitioning, optimize Spark config
Large (10-100TB): Add dedicated SQL pools, larger clusters
Very Large (100TB+): Consider Data Lake zones, Photon, streaming
```"

---

## Final Summary

### Q26: Summarize the key accomplishments of this project.

**Answer:**
"I designed and implemented a complete, production-ready Azure data platform from scratch:

**Key Accomplishments:**

**1. End-to-End Data Pipeline:**
- Automated ingestion from raw files to business-ready analytics
- Bronze → Silver → Gold medallion architecture
- Handles data quality, transformations, and aggregations
- Daily automated execution

**2. Infrastructure as Code:**
- 100% Terraform-managed infrastructure
- 7 separate modules for different Azure services
- Reusable, maintainable, version-controlled
- Can deploy entire platform in < 30 minutes

**3. Security and Compliance:**
- Azure AD-based RBAC with 3 role groups
- All secrets in Key Vault
- Audit logs for all data access
- Network security and encryption at rest/in transit

**4. CI/CD Automation:**
- GitHub Actions for automated deployments
- Terraform plan on every PR
- Manual approval gates for production
- Automated Databricks notebook deployment

**5. Cost Optimization:**
- Auto-scaling clusters (save 60-70%)
- Auto-pause when idle
- Serverless SQL (pay-per-query)
- Storage lifecycle policies

**6. Monitoring and Operations:**
- Comprehensive metrics and alerting
- Pipeline failure notifications
- Cost anomaly detection
- Data quality tracking

**Technologies Integrated:**
- Azure Active Directory (RBAC)
- Azure Storage (Data Lake Gen2)
- Azure Databricks (Data processing)
- Azure Synapse (Analytics)
- Azure Data Factory (Orchestration)
- Azure Key Vault (Secrets)
- Terraform (IaC)
- GitHub Actions (CI/CD)

**Business Value:**
- Analysts can self-serve data through SQL
- Data engineers focus on value-add work
- Reduced manual operations by 80%
- Scalable to 10-100x data volume
- Audit-ready for compliance

**What I'd Do Next:**
- Add Power BI dashboards
- Implement real-time streaming for urgent data
- Add ML models for predictive analytics
- Expand to multi-region for disaster recovery
- Add data catalog (Purview) for discovery"

---

## Interview Tips

### How to Present This Project:

1. **Start with Business Context:**
   - "The company needed a scalable analytics platform for customer transaction data"
   - "Business users needed self-service access to data"

2. **Explain the Architecture:**
   - Draw the diagram on whiteboard
   - Explain data flow clearly
   - Highlight key decision points

3. **Dive into Technical Details:**
   - Be prepared to explain any component deeply
   - Show Terraform code if asked
   - Explain security measures

4. **Discuss Challenges:**
   - "Initially struggled with Databricks authentication"
   - "Learned the importance of data partitioning for performance"
   - "Had to optimize Spark config for larger datasets"

5. **Highlight Best Practices:**
   - IaC for all infrastructure
   - GitOps for deployments
   - Security-first approach
   - Cost optimization

6. **Be Honest:**
   - If you haven't implemented something, say so
   - "I designed this but haven't deployed to production yet"
   - "I would like to add X in the future"

### Common Follow-up Questions:

- "How would you handle multi-region?" → Active-passive setup, geo-replication
- "What about disaster recovery?" → Backup strategies, point-in-time restore
- "How do you handle schema changes?" → Schema evolution, backward compatibility
- "Performance issues?" → Optimization strategies discussed above
- "Cost got too high?" → Cost optimization measures
