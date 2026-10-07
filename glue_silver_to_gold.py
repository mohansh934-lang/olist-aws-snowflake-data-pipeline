import sys

from awsglue.context import GlueContext
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F

# Arguments come from the Glue job definition (Terraform) or from Step Functions later
args = getResolvedOptions(sys.argv, ["JOB_NAME", "bucket", "ingest_date"])
bucket = args["bucket"]

spark = GlueContext(SparkContext.getOrCreate()).spark_session


def read_silver(table):
    """Read all ingest_date folders of a silver table; ingest_date becomes a string column."""
    df = spark.read.parquet(f"s3://{bucket}/silver/olist/{table}/")
    return df.withColumn("ingest_date", F.col("ingest_date").cast("string"))


orders_all = read_silver("orders")
items_all = read_silver("order_items")

# "latest" = newest snapshot found in silver
ingest_date = args["ingest_date"]
if ingest_date == "latest":
    ingest_date = orders_all.agg(F.max("ingest_date")).first()[0]

print(f"[gold] using silver snapshot ingest_date={ingest_date}")

orders_all.filter(F.col("ingest_date") == ingest_date).createOrReplaceTempView("orders")
items_all.filter(F.col("ingest_date") == ingest_date).createOrReplaceTempView("order_items")

# ---------- gold 1: daily sales ----------
daily_sales = spark.sql("""
    SELECT to_date(o.order_purchase_timestamp)  AS order_date,
           count(DISTINCT o.order_id)           AS orders,
           count(*)                             AS items,
           round(sum(i.price), 2)               AS revenue,
           round(sum(i.freight_value), 2)       AS freight
    FROM orders o
    JOIN order_items i ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY 1
""")

# ---------- gold 2: delivery performance by month ----------
delivery = spark.sql("""
    SELECT date_format(order_purchase_timestamp, 'yyyy-MM') AS month,
           count(*) AS delivered_orders,
           round(avg(floor((unix_timestamp(order_delivered_customer_date)
                          - unix_timestamp(order_purchase_timestamp)) / 86400)), 1) AS avg_delivery_days,
           round(100.0 * avg(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date
                                  THEN 1 ELSE 0 END), 1) AS pct_late
    FROM orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
    GROUP BY 1
""")

# mode("overwrite") replaces old files, so the job can run again and again.
# coalesce(1) writes one file per table (small tables, no small-files problem).
for name, df in [("daily_sales", daily_sales), ("delivery_performance", delivery)]:
    path = f"s3://{bucket}/gold/olist/{name}/"
    df.coalesce(1).write.mode("overwrite").parquet(path)
    print(f"[gold] {name}: {df.count()} rows -> {path}")
