-- Synapse SQL Scripts for Creating External Tables and Views
-- These views provide SQL access to the Gold layer data for analysts and BI tools

-- ============================================
-- 1. Create Database and Schema
-- ============================================

-- Create database for analytics
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'CustomerAnalytics')
BEGIN
    CREATE DATABASE CustomerAnalytics;
END;
GO

USE CustomerAnalytics;
GO

-- Create schema for Gold layer
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'gold')
BEGIN
    EXEC('CREATE SCHEMA gold');
END;
GO

-- ============================================
-- 2. Create Master Key and Database Credential
-- ============================================

-- Create master key for encryption
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'YourStrongPassword123!';
END;
GO

-- Create database scoped credential using managed identity
-- Replace <storage-account-name> with your actual storage account name
IF NOT EXISTS (SELECT * FROM sys.database_credentials WHERE name = 'StorageCredential')
BEGIN
    CREATE DATABASE SCOPED CREDENTIAL StorageCredential
    WITH IDENTITY = 'Managed Identity';
END;
GO

-- ============================================
-- 3. Create External Data Source
-- ============================================

-- Replace <storage-account-name> with your actual storage account name
DECLARE @StorageAccount NVARCHAR(100) = '<storage-account-name>';
DECLARE @DataSourceLocation NVARCHAR(200) = 'abfss://gold@' + @StorageAccount + '.dfs.core.windows.net';

IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'GoldStorage')
BEGIN
    EXEC('
        CREATE EXTERNAL DATA SOURCE GoldStorage
        WITH (
            LOCATION = ''' + @DataSourceLocation + ''',
            CREDENTIAL = StorageCredential
        )
    ');
END;
GO

-- ============================================
-- 4. Create External File Format
-- ============================================

-- Parquet format
IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'ParquetFormat')
BEGIN
    CREATE EXTERNAL FILE FORMAT ParquetFormat
    WITH (
        FORMAT_TYPE = PARQUET,
        DATA_COMPRESSION = 'org.apache.hadoop.io.compress.SnappyCodec'
    );
END;
GO

-- Delta format (for Delta Lake tables)
IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'DeltaFormat')
BEGIN
    CREATE EXTERNAL FILE FORMAT DeltaFormat
    WITH (
        FORMAT_TYPE = DELTA
    );
END;
GO

-- ============================================
-- 5. Create External Tables for Gold Layer
-- ============================================

-- Daily Sales Summary
DROP EXTERNAL TABLE IF EXISTS gold.daily_sales_summary;
GO

CREATE EXTERNAL TABLE gold.daily_sales_summary
(
    transaction_date DATE,
    total_transactions BIGINT,
    total_revenue DECIMAL(18,2),
    avg_transaction_value DECIMAL(18,2),
    unique_customers BIGINT,
    total_items_sold BIGINT,
    revenue_per_customer DECIMAL(18,2),
    load_timestamp DATETIME2
)
WITH (
    LOCATION = 'daily_sales_summary',
    DATA_SOURCE = GoldStorage,
    FILE_FORMAT = DeltaFormat
);
GO

-- Product Category Performance
DROP EXTERNAL TABLE IF EXISTS gold.product_category_performance;
GO

CREATE EXTERNAL TABLE gold.product_category_performance
(
    product_category VARCHAR(100),
    total_transactions BIGINT,
    total_revenue DECIMAL(18,2),
    avg_transaction_value DECIMAL(18,2),
    total_quantity BIGINT,
    unique_customers BIGINT,
    revenue_rank INT,
    load_timestamp DATETIME2
)
WITH (
    LOCATION = 'product_category_performance',
    DATA_SOURCE = GoldStorage,
    FILE_FORMAT = DeltaFormat
);
GO

-- Customer Segmentation
DROP EXTERNAL TABLE IF EXISTS gold.customer_segmentation;
GO

CREATE EXTERNAL TABLE gold.customer_segmentation
(
    customer_id VARCHAR(50),
    total_transactions BIGINT,
    total_spent DECIMAL(18,2),
    avg_transaction_value DECIMAL(18,2),
    last_transaction_date DATE,
    first_transaction_date DATE,
    customer_segment VARCHAR(20),
    frequency_segment VARCHAR(20),
    days_since_last_transaction INT,
    customer_lifetime_days INT,
    load_timestamp DATETIME2
)
WITH (
    LOCATION = 'customer_segmentation',
    DATA_SOURCE = GoldStorage,
    FILE_FORMAT = DeltaFormat
);
GO

-- Store Performance
DROP EXTERNAL TABLE IF EXISTS gold.store_performance;
GO

CREATE EXTERNAL TABLE gold.store_performance
(
    store_location VARCHAR(100),
    total_transactions BIGINT,
    total_revenue DECIMAL(18,2),
    avg_transaction_value DECIMAL(18,2),
    unique_customers BIGINT,
    product_variety BIGINT,
    revenue_rank INT,
    load_timestamp DATETIME2
)
WITH (
    LOCATION = 'store_performance',
    DATA_SOURCE = GoldStorage,
    FILE_FORMAT = DeltaFormat
);
GO

-- Payment Method Analysis
DROP EXTERNAL TABLE IF EXISTS gold.payment_method_analysis;
GO

CREATE EXTERNAL TABLE gold.payment_method_analysis
(
    payment_method VARCHAR(50),
    total_transactions BIGINT,
    total_revenue DECIMAL(18,2),
    avg_transaction_value DECIMAL(18,2),
    transaction_percentage DECIMAL(5,2),
    load_timestamp DATETIME2
)
WITH (
    LOCATION = 'payment_method_analysis',
    DATA_SOURCE = GoldStorage,
    FILE_FORMAT = DeltaFormat
);
GO

-- ============================================
-- 6. Create Business Views
-- ============================================

-- View: Top Performing Categories (Last 30 Days)
CREATE OR ALTER VIEW gold.vw_top_categories_last_30_days
AS
SELECT TOP 10
    product_category,
    total_revenue,
    total_transactions,
    avg_transaction_value,
    revenue_rank
FROM gold.product_category_performance
WHERE load_timestamp >= DATEADD(day, -30, GETDATE())
ORDER BY total_revenue DESC;
GO

-- View: High Value Customers
CREATE OR ALTER VIEW gold.vw_high_value_customers
AS
SELECT
    customer_id,
    total_spent,
    total_transactions,
    customer_segment,
    frequency_segment,
    days_since_last_transaction,
    CASE
        WHEN days_since_last_transaction <= 30 THEN 'Active'
        WHEN days_since_last_transaction <= 90 THEN 'At Risk'
        ELSE 'Churned'
    END AS customer_status
FROM gold.customer_segmentation
WHERE customer_segment = 'HIGH_VALUE'
ORDER BY total_spent DESC;
GO

-- View: Monthly Revenue Trend
CREATE OR ALTER VIEW gold.vw_monthly_revenue_trend
AS
SELECT
    YEAR(transaction_date) AS year,
    MONTH(transaction_date) AS month,
    DATEFROMPARTS(YEAR(transaction_date), MONTH(transaction_date), 1) AS month_start_date,
    SUM(total_revenue) AS monthly_revenue,
    SUM(total_transactions) AS monthly_transactions,
    AVG(avg_transaction_value) AS avg_transaction_value,
    SUM(unique_customers) AS unique_customers
FROM gold.daily_sales_summary
GROUP BY YEAR(transaction_date), MONTH(transaction_date)
ORDER BY year, month;
GO

-- View: Store Comparison Dashboard
CREATE OR ALTER VIEW gold.vw_store_comparison
AS
SELECT
    store_location,
    total_revenue,
    total_transactions,
    unique_customers,
    avg_transaction_value,
    revenue_rank,
    ROUND(total_revenue * 100.0 / SUM(total_revenue) OVER (), 2) AS revenue_share_percentage
FROM gold.store_performance
ORDER BY revenue_rank;
GO

-- View: Payment Method Preferences
CREATE OR ALTER VIEW gold.vw_payment_preferences
AS
SELECT
    payment_method,
    total_transactions,
    total_revenue,
    transaction_percentage,
    avg_transaction_value,
    RANK() OVER (ORDER BY total_transactions DESC) AS popularity_rank
FROM gold.payment_method_analysis
ORDER BY total_transactions DESC;
GO

-- ============================================
-- 7. Create Sample Queries for Analysts
-- ============================================

-- Sample Query 1: Revenue Trend Last 7 Days
-- SELECT
--     transaction_date,
--     total_revenue,
--     total_transactions,
--     unique_customers
-- FROM gold.daily_sales_summary
-- WHERE transaction_date >= DATEADD(day, -7, CAST(GETDATE() AS DATE))
-- ORDER BY transaction_date DESC;

-- Sample Query 2: Customer Churn Analysis
-- SELECT
--     customer_segment,
--     CASE
--         WHEN days_since_last_transaction <= 30 THEN 'Active'
--         WHEN days_since_last_transaction <= 90 THEN 'At Risk'
--         ELSE 'Churned'
--     END AS status,
--     COUNT(*) AS customer_count,
--     SUM(total_spent) AS total_revenue
-- FROM gold.customer_segmentation
-- GROUP BY customer_segment,
--     CASE
--         WHEN days_since_last_transaction <= 30 THEN 'Active'
--         WHEN days_since_last_transaction <= 90 THEN 'At Risk'
--         ELSE 'Churned'
--     END
-- ORDER BY customer_segment, status;

-- Sample Query 3: Product Category Performance by Store
-- SELECT
--     s.store_location,
--     c.product_category,
--     c.total_revenue,
--     c.total_transactions
-- FROM gold.store_performance s
-- CROSS JOIN gold.product_category_performance c
-- ORDER BY s.store_location, c.total_revenue DESC;

PRINT 'All external tables and views created successfully!';
