import os

import boto3
import snowflake.connector
from cryptography.hazmat.primitives import serialization

ssm = boto3.client("ssm")
TABLES = ("daily_sales", "delivery_performance")


def private_key_der():
    """Read the private key from SSM Parameter Store and convert it to the format Snowflake wants."""
    pem = ssm.get_parameter(Name=os.environ["KEY_PARAM"], WithDecryption=True)["Parameter"]["Value"]
    key = serialization.load_pem_private_key(pem.encode(), password=None)
    return key.private_bytes(
        serialization.Encoding.DER,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )


def handler(event, context):
    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key=private_key_der(),
        role=os.environ["SNOWFLAKE_ROLE"],
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
    )
    try:
        cur = conn.cursor()

        # The procedure empties each gold table and reloads it from S3
        cur.execute("CALL olist_db.gold.load_gold()")
        message = cur.fetchone()[0]

        # Guard: an empty table means something upstream went wrong, so fail loudly
        counts = {}
        for table in TABLES:
            cur.execute(f"SELECT count(*) FROM olist_db.gold.{table}")
            counts[table] = cur.fetchone()[0]
        print(f"[load] {message} {counts}")

        empty = [t for t, n in counts.items() if n == 0]
        if empty:
            raise RuntimeError(f"Tables are empty after load: {empty}")

        return {"status": message, "counts": counts}
    finally:
        conn.close()
