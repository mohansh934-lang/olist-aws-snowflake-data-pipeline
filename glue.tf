# Uploads the PySpark script to s3://<bucket>/scripts/ (re-uploads when the file changes)
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.lake.id
  key    = "scripts/glue_raw_to_silver.py"
  source = "${path.module}/glue_raw_to_silver.py"
  etag   = filemd5("${path.module}/glue_raw_to_silver.py")
}

# The Glue job itself. Small and capped so it cannot run up a bill.
resource "aws_glue_job" "raw_to_silver" {
  name              = "olist-raw-to-silver"
  role_arn          = aws_iam_role.svc["glue"].arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15 # minutes, job is killed after this
  max_retries       = 0

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.lake.bucket}/${aws_s3_object.glue_script.key}"
  }

  default_arguments = {
    "--BUCKET"      = aws_s3_bucket.lake.bucket
    "--INGEST_DATE" = "2026-10-02"
    "--job-language" = "python"
  }
}
