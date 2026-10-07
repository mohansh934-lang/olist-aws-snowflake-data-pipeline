# Step 3.1: Glue job that builds the gold tables (rerunnable)
# Goes in the same folder as main.tf, iam.tf, snowflake.tf, glue.tf
# Needs glue_silver_to_gold.py in the same folder.

# Upload the script to S3 (etag makes Terraform re-upload when the script changes)
resource "aws_s3_object" "gold_script" {
  bucket = aws_s3_bucket.lake.id
  key    = "scripts/glue_silver_to_gold.py"
  source = "${path.module}/glue_silver_to_gold.py"
  etag   = filemd5("${path.module}/glue_silver_to_gold.py")
}

# The Glue job: 2 small workers, stops by itself after 15 minutes
resource "aws_glue_job" "silver_to_gold" {
  name              = "olist-silver-to-gold"
  role_arn          = aws_iam_role.svc["glue"].arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.lake.bucket}/${aws_s3_object.gold_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--bucket"      = aws_s3_bucket.lake.bucket
    "--ingest_date" = "latest"
  }
}
