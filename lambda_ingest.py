import os
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]
SRC_PREFIX = "source/olist/"


def handler(event, context):
    # Use the date passed in (for re-runs of an old day), otherwise today in UTC
    ingest_date = (event or {}).get("ingest_date") or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    datetime.strptime(ingest_date, "%Y-%m-%d")  # fails fast on a badly formatted date

    dst_prefix = f"raw/olist/ingest_date={ingest_date}/"
    copied = 0

    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=SRC_PREFIX):
        for obj in page.get("Contents", []):
            name = obj["Key"][len(SRC_PREFIX):]
            if not name.endswith(".csv"):
                continue
            # Copy happens inside S3, nothing is downloaded. Same date again = overwrite, so reruns are safe.
            s3.copy_object(
                Bucket=BUCKET,
                Key=dst_prefix + name,
                CopySource={"Bucket": BUCKET, "Key": obj["Key"]},
            )
            copied += 1

    if copied == 0:
        raise RuntimeError(f"No CSV files found under s3://{BUCKET}/{SRC_PREFIX}")

    print(f"[ingest] copied {copied} files to s3://{BUCKET}/{dst_prefix}")
    return {"ingest_date": ingest_date, "files": copied}
