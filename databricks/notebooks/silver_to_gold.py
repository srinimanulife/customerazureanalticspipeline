# Databricks notebook source
# MAGIC %md
# MAGIC # Silver to Gold Transformation
# MAGIC
# MAGIC This notebook reads cleansed data from the Silver layer, applies business logic,
# MAGIC creates aggregations, and writes business-ready data to the Gold layer in Delta format.
# MAGIC
# MAGIC **Input**: Silver container (Parquet files)
# MAGIC **Output**: Gold container (Delta tables)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. Import Libraries and Setup

# COMMAND ----------

from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.window import Window
from datetime import datetime

# Get parameters from Data Factory or set defaults
dbutils.widgets.text("storage_account", "", "Storage Account Name")
dbutils.widgets.text("source_container", "silver", "Source Container")
dbutils.widgets.text("target_container", "gold", "Target Container")
dbutils.widgets.text("source_path", "transactions", "Source Path")

storage_account = dbutils.widgets.get("storage_account")
source_container = dbutils.widgets.get("source_container")
target_container = dbutils.widgets.get("target_container")
source_path = dbutils.widgets.get("source_path")

print(f"Storage Account: {storage_account}")
print(f"Source: {source_container}/{source_path}")
print(f"Target: {target_container}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Configure Storage Access

# COMMAND ----------

silver_path = f"abfss://{source_container}@{storage_account}.dfs.core.windows.net/{source_path}"
gold_path = f"abfss://{target_container}@{storage_account}.dfs.core.windows.net"

print(f"Reading from: {silver_path}")
print(f"Writing to: {gold_path}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. Read Silver Data

# COMMAND ----------

try:
    silver_df = spark.read \
        .format("parquet") \
        .load(silver_path) \
        .filter(col("is_valid") == True)

    print(f"Successfully read {silver_df.count()} records from silver layer")
    silver_df.printSchema()
    display(silver_df.limit(5))

except Exception as e:
    print(f"Error reading silver data: {str(e)}")
    raise

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Business Aggregations

# COMMAND ----------

# MAGIC %md
# MAGIC ### 4.1 Daily Sales Summary

# COMMAND ----------

daily_sales = silver_df.groupBy("transaction_date") \
    .agg(
        count("transaction_id").alias("total_transactions"),
        sum("amount").alias("total_revenue"),
        avg("amount").alias("avg_transaction_value"),
        countDistinct("customer_id").alias("unique_customers"),
        sum("quantity").alias("total_items_sold")
    ) \
    .withColumn("revenue_per_customer", round(col("total_revenue") / col("unique_customers"), 2)) \
    .withColumn("load_timestamp", current_timestamp()) \
    .orderBy("transaction_date")

print(f"Daily Sales Summary: {daily_sales.count()} days")
display(daily_sales)

# COMMAND ----------

# MAGIC %md
# MAGIC ### 4.2 Product Category Performance

# COMMAND ----------

category_performance = silver_df.groupBy("product_category") \
    .agg(
        count("transaction_id").alias("total_transactions"),
        sum("amount").alias("total_revenue"),
        avg("amount").alias("avg_transaction_value"),
        sum("quantity").alias("total_quantity"),
        countDistinct("customer_id").alias("unique_customers")
    ) \
    .withColumn("revenue_rank", dense_rank().over(Window.orderBy(desc("total_revenue")))) \
    .withColumn("load_timestamp", current_timestamp()) \
    .orderBy(desc("total_revenue"))

print(f"Product Categories: {category_performance.count()}")
display(category_performance)

# COMMAND ----------

# MAGIC %md
# MAGIC ### 4.3 Customer Segmentation

# COMMAND ----------

# Calculate customer metrics
customer_metrics = silver_df.groupBy("customer_id") \
    .agg(
        count("transaction_id").alias("total_transactions"),
        sum("amount").alias("total_spent"),
        avg("amount").alias("avg_transaction_value"),
        max("transaction_date").alias("last_transaction_date"),
        min("transaction_date").alias("first_transaction_date"),
        collect_set("product_category").alias("product_categories")
    )

# Add customer segments based on spending
customer_segmentation = customer_metrics \
    .withColumn("customer_segment",
                when(col("total_spent") >= 1000, "HIGH_VALUE")
                .when(col("total_spent") >= 500, "MEDIUM_VALUE")
                .otherwise("LOW_VALUE")) \
    .withColumn("frequency_segment",
                when(col("total_transactions") >= 10, "FREQUENT")
                .when(col("total_transactions") >= 5, "REGULAR")
                .otherwise("OCCASIONAL")) \
    .withColumn("days_since_last_transaction",
                datediff(current_date(), col("last_transaction_date"))) \
    .withColumn("customer_lifetime_days",
                datediff(col("last_transaction_date"), col("first_transaction_date"))) \
    .withColumn("load_timestamp", current_timestamp())

print(f"Customer Segmentation: {customer_segmentation.count()} customers")
display(customer_segmentation.limit(10))

# COMMAND ----------

# MAGIC %md
# MAGIC ### 4.4 Store Location Performance

# COMMAND ----------

store_performance = silver_df.groupBy("store_location") \
    .agg(
        count("transaction_id").alias("total_transactions"),
        sum("amount").alias("total_revenue"),
        avg("amount").alias("avg_transaction_value"),
        countDistinct("customer_id").alias("unique_customers"),
        countDistinct("product_category").alias("product_variety")
    ) \
    .withColumn("revenue_rank", dense_rank().over(Window.orderBy(desc("total_revenue")))) \
    .withColumn("load_timestamp", current_timestamp()) \
    .orderBy(desc("total_revenue"))

print(f"Store Locations: {store_performance.count()}")
display(store_performance)

# COMMAND ----------

# MAGIC %md
# MAGIC ### 4.5 Payment Method Analysis

# COMMAND ----------

payment_analysis = silver_df.groupBy("payment_method") \
    .agg(
        count("transaction_id").alias("total_transactions"),
        sum("amount").alias("total_revenue"),
        avg("amount").alias("avg_transaction_value")
    ) \
    .withColumn("transaction_percentage",
                round(col("total_transactions") * 100.0 / sum("total_transactions").over(Window.partitionBy()), 2)) \
    .withColumn("load_timestamp", current_timestamp()) \
    .orderBy(desc("total_transactions"))

print(f"Payment Methods: {payment_analysis.count()}")
display(payment_analysis)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5. Write to Gold Layer (Delta Format)

# COMMAND ----------

# MAGIC %md
# MAGIC ### 5.1 Write Daily Sales Summary

# COMMAND ----------

daily_sales_path = f"{gold_path}/daily_sales_summary"

try:
    daily_sales.write \
        .format("delta") \
        .mode("overwrite") \
        .option("overwriteSchema", "true") \
        .save(daily_sales_path)

    print(f"Successfully wrote daily sales summary to: {daily_sales_path}")

except Exception as e:
    print(f"Error writing daily sales: {str(e)}")
    raise

# COMMAND ----------

# MAGIC %md
# MAGIC ### 5.2 Write Category Performance

# COMMAND ----------

category_path = f"{gold_path}/product_category_performance"

try:
    category_performance.write \
        .format("delta") \
        .mode("overwrite") \
        .option("overwriteSchema", "true") \
        .save(category_path)

    print(f"Successfully wrote category performance to: {category_path}")

except Exception as e:
    print(f"Error writing category performance: {str(e)}")
    raise

# COMMAND ----------

# MAGIC %md
# MAGIC ### 5.3 Write Customer Segmentation

# COMMAND ----------

customer_path = f"{gold_path}/customer_segmentation"

try:
    customer_segmentation.write \
        .format("delta") \
        .mode("overwrite") \
        .option("overwriteSchema", "true") \
        .save(customer_path)

    print(f"Successfully wrote customer segmentation to: {customer_path}")

except Exception as e:
    print(f"Error writing customer segmentation: {str(e)}")
    raise

# COMMAND ----------

# MAGIC %md
# MAGIC ### 5.4 Write Store Performance

# COMMAND ----------

store_path = f"{gold_path}/store_performance"

try:
    store_performance.write \
        .format("delta") \
        .mode("overwrite") \
        .option("overwriteSchema", "true") \
        .save(store_path)

    print(f"Successfully wrote store performance to: {store_path}")

except Exception as e:
    print(f"Error writing store performance: {str(e)}")
    raise

# COMMAND ----------

# MAGIC %md
# MAGIC ### 5.5 Write Payment Analysis

# COMMAND ----------

payment_path = f"{gold_path}/payment_method_analysis"

try:
    payment_analysis.write \
        .format("delta") \
        .mode("overwrite") \
        .option("overwriteSchema", "true") \
        .save(payment_path)

    print(f"Successfully wrote payment analysis to: {payment_path}")

except Exception as e:
    print(f"Error writing payment analysis: {str(e)}")
    raise

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6. Create Delta Tables for Synapse Integration

# COMMAND ----------

# Register Delta tables (optional - for Databricks SQL access)
spark.sql(f"""
    CREATE TABLE IF NOT EXISTS gold.daily_sales_summary
    USING DELTA
    LOCATION '{daily_sales_path}'
""")

spark.sql(f"""
    CREATE TABLE IF NOT EXISTS gold.customer_segmentation
    USING DELTA
    LOCATION '{customer_path}'
""")

print("Delta tables created successfully")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 7. Summary Statistics

# COMMAND ----------

summary = {
    "total_transactions_processed": silver_df.count(),
    "daily_summaries_created": daily_sales.count(),
    "product_categories": category_performance.count(),
    "unique_customers": customer_segmentation.count(),
    "store_locations": store_performance.count(),
    "processing_timestamp": datetime.now().isoformat()
}

print("Gold Layer Summary:")
for key, value in summary.items():
    print(f"  {key}: {value}")

# COMMAND ----------

# Return success status to Data Factory
dbutils.notebook.exit("SUCCESS")
