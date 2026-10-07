import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F

# Job arguments (set in glue.tf as default_arguments, can be overridden per run)
args = getResolvedOptions(sys.argv, ["JOB_NAME", "BUCKET", "INGEST_DATE"])
bucket = args["BUCKET"]
ingest_date = args["INGEST_DATE"]

sc = SparkContext()
glue = GlueContext(sc)
spark = glue.spark_session
job = Job(glue)
job.init(args["JOB_NAME"], args)

SRC = f"s3://{bucket}/raw/olist/ingest_date={ingest_date}"
DST = f"s3://{bucket}/silver/olist"

# For each table: csv file, dedupe keys, and which columns need a type cast.
# Everything else stays string (zip codes must stay string to keep leading zeros).
TABLES = {
    "orders": {
        "file": "olist_orders_dataset.csv",
        "keys": ["order_id"],
        "ts": [
            "order_purchase_timestamp",
            "order_approved_at",
            "order_delivered_carrier_date",
            "order_delivered_customer_date",
            "order_estimated_delivery_date",
        ],
    },
    "customers": {
        "file": "olist_customers_dataset.csv",
        "keys": ["customer_id"],
    },
    "order_items": {
        "file": "olist_order_items_dataset.csv",
        "keys": ["order_id", "order_item_id"],
        "ts": ["shipping_limit_date"],
        "int": ["order_item_id"],
        "dbl": ["price", "freight_value"],
    },
    "order_payments": {
        "file": "olist_order_payments_dataset.csv",
        "keys": ["order_id", "payment_sequential"],
        "int": ["payment_sequential", "payment_installments"],
        "dbl": ["payment_value"],
    },
    "order_reviews": {
        "file": "olist_order_reviews_dataset.csv",
        "keys": ["review_id", "order_id"],
        "ts": ["review_creation_date", "review_answer_timestamp"],
        "int": ["review_score"],
    },
    "products": {
        "file": "olist_products_dataset.csv",
        "keys": ["product_id"],
        "int": [
            "product_name_lenght",
            "product_description_lenght",
            "product_photos_qty",
            "product_weight_g",
            "product_length_cm",
            "product_height_cm",
            "product_width_cm",
        ],
        # source file has a typo ("lenght"), fix it in silver
        "rename": {
            "product_name_lenght": "product_name_length",
            "product_description_lenght": "product_description_length",
        },
    },
    "sellers": {
        "file": "olist_sellers_dataset.csv",
        "keys": ["seller_id"],
    },
    "geolocation": {
        "file": "olist_geolocation_dataset.csv",
        "keys": None,  # no natural key, drop fully identical rows
        "dbl": ["geolocation_lat", "geolocation_lng"],
    },
    "category_translation": {
        "file": "product_category_name_translation.csv",
        "keys": ["product_category_name"],
    },
}

for name, cfg in TABLES.items():
    df = (
        spark.read.option("header", True)
        .option("multiLine", True)  # review comments contain line breaks
        .option("quote", '"')
        .option("escape", '"')
        .csv(f"{SRC}/{cfg['file']}")
    )

    # trim strings, empty string -> null
    for col, dtype in df.dtypes:
        if dtype == "string":
            trimmed = F.trim(F.col(col))
            df = df.withColumn(
                col, F.when(trimmed == "", F.lit(None)).otherwise(trimmed)
            )

    # type casts
    for col in cfg.get("ts", []):
        df = df.withColumn(col, F.to_timestamp(F.col(col)))
    for col in cfg.get("int", []):
        df = df.withColumn(col, F.col(col).cast("int"))
    for col in cfg.get("dbl", []):
        df = df.withColumn(col, F.col(col).cast("double"))

    # rename typo columns
    for old, new in cfg.get("rename", {}).items():
        df = df.withColumnRenamed(old, new)

    # drop duplicates
    keys = cfg.get("keys")
    # keys are original column names, renamed columns are not used as keys
    df = df.dropDuplicates(keys) if keys else df.dropDuplicates()

    df = df.cache()
    row_count = df.count()

    # overwrite only this table's folder for this date, so re-running is safe
    out = f"{DST}/{name}/ingest_date={ingest_date}/"
    df.write.mode("overwrite").parquet(out)
    df.unpersist()

    print(f"[silver] {name}: {row_count} rows -> {out}")

job.commit()
