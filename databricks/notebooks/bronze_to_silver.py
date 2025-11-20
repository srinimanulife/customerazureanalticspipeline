# Databricks notebook source
# MAGIC %md
# MAGIC # Bronze to Silver Transformation
# MAGIC
# MAGIC This notebook reads raw CSV data from the Bronze layer, applies data quality checks,
# MAGIC cleanses the data, and writes it to the Silver layer in Parquet format.
# MAGIC
# MAGIC **Input**: Bronze container (CSV files)
# MAGIC **Output**: Silver container (Parquet files)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. Import Libraries and Setup

# COMMAND ----------

from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
from datetime import datetime

# Get parameters from Data Factory or set defaults
dbutils.widgets.text("storage_account", "", "Storage Account Name")
dbutils.widgets.text("source_container", "bronze", "Source Container")
dbutils.widgets.text("target_container", "silver", "Target Container")
dbutils.widgets.text("source_path", "transactions", "Source Path")

storage_account = dbutils.widgets.get("storage_account")
source_container = dbutils.widgets.get("source_container")
target_container = dbutils.widgets.get("target_container")
source_path = dbutils.widgets.get("source_path")

print(f"Storage Account: {storage_account}")
print(f"Source: {source_container}/{source_path}")
print(f"Target: {target_container}/{source_path}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Configure Storage Access

# COMMAND ----------

# Access storage using service principal (credentials stored in Key Vault)
# Alternative: Use managed identity for production

# For ADLS Gen2
bronze_path = f"abfss://{source_container}@{storage_account}.dfs.core.windows.net/{source_path}"
silver_path = f"abfss://{target_container}@{storage_account}.dfs.core.windows.net/{source_path}"

print(f"Reading from: {bronze_path}")
print(f"Writing to: {silver_path}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. Define Schema

# COMMAND ----------

# Define schema for transactions data
transaction_schema = StructType([
    StructField("transaction_id", StringType(), False),
    StructField("customer_id", StringType(), False),
    StructField("transaction_date", StringType(), False),
    StructField("amount", StringType(), False),
    StructField("product_category", StringType(), True),
    StructField("payment_method", StringType(), True),
    StructField("store_location", StringType(), True),
    StructField("quantity", StringType(), True)
])

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Read Bronze Data

# COMMAND ----------

try:
    bronze_df = spark.read \
        .format("csv") \
        .option("header", "true") \
        .option("inferSchema", "false") \
        .schema(transaction_schema) \
        .load(bronze_path)

    print(f"Successfully read {bronze_df.count()} records from bronze layer")
    bronze_df.printSchema()
    display(bronze_df.limit(5))

except Exception as e:
    print(f"Error reading bronze data: {str(e)}")
    raise

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5. Data Quality Checks and Cleansing

# COMMAND ----------

# Add ingestion timestamp
silver_df = bronze_df.withColumn("ingestion_timestamp", current_timestamp())

# Data quality checks and transformations
silver_df = silver_df \
    .filter(col("transaction_id").isNotNull()) \
    .filter(col("customer_id").isNotNull()) \
    .withColumn("transaction_date", to_date(col("transaction_date"), "yyyy-MM-dd")) \
    .withColumn("amount", col("amount").cast(DecimalType(10, 2))) \
    .withColumn("quantity", col("quantity").cast(IntegerType())) \
    .withColumn("product_category", trim(upper(col("product_category")))) \
    .withColumn("payment_method", trim(upper(col("payment_method")))) \
    .withColumn("store_location", trim(upper(col("store_location")))) \
    .filter(col("amount") > 0) \
    .filter(col("quantity") > 0)

# Add data quality flag
silver_df = silver_df \
    .withColumn("is_valid",
                when((col("amount").isNotNull()) &
                     (col("transaction_date").isNotNull()) &
                     (col("quantity").isNotNull()), True)
                .otherwise(False))

# Drop duplicates based on transaction_id
silver_df = silver_df.dropDuplicates(["transaction_id"])

print(f"After cleansing: {silver_df.count()} valid records")
display(silver_df.limit(5))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6. Data Quality Metrics

# COMMAND ----------

# Calculate data quality metrics
total_bronze_records = bronze_df.count()
total_silver_records = silver_df.count()
rejected_records = total_bronze_records - total_silver_records
quality_rate = (total_silver_records / total_bronze_records * 100) if total_bronze_records > 0 else 0

metrics = {
    "total_bronze_records": total_bronze_records,
    "total_silver_records": total_silver_records,
    "rejected_records": rejected_records,
    "quality_rate_percent": round(quality_rate, 2),
    "processing_timestamp": datetime.now().isoformat()
}

print("Data Quality Metrics:")
for key, value in metrics.items():
    print(f"  {key}: {value}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 7. Write to Silver Layer

# COMMAND ----------

try:
    silver_df.write \
        .format("parquet") \
        .mode("overwrite") \
        .partitionBy("transaction_date") \
        .option("compression", "snappy") \
        .save(silver_path)

    print(f"Successfully wrote {silver_df.count()} records to silver layer")
    print(f"Location: {silver_path}")

except Exception as e:
    print(f"Error writing to silver layer: {str(e)}")
    raise

# COMMAND ----------

# MAGIC %md
# MAGIC ## 8. Verify Write

# COMMAND ----------

# Verify the data was written correctly
verify_df = spark.read.parquet(silver_path)
print(f"Verification: Read {verify_df.count()} records from silver layer")
display(verify_df.limit(5))

# COMMAND ----------

# Return success status to Data Factory
dbutils.notebook.exit("SUCCESS")
