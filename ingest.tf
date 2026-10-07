# Step 3.5: ingest Lambda. Simulates "new data arrives every day".
# Same folder as the other .tf files. Needs lambda_ingest.py in the same folder.
# Run `terraform init` once more, because this uses the small "archive" provider to make the zip.

data "archive_file" "ingest" {
  type        = "zip"
  source_file = "${path.module}/lambda_ingest.py"
  output_path = "${path.module}/lambda_ingest.zip"
}

# Reuses the olist-batch-lambda role, which already has read/write on our bucket
resource "aws_lambda_function" "ingest" {
  function_name    = "olist-batch-ingest"
  role             = aws_iam_role.svc["lambda"].arn
  runtime          = "python3.12"
  handler          = "lambda_ingest.handler"
  filename         = data.archive_file.ingest.output_path
  source_code_hash = data.archive_file.ingest.output_base64sha256
  timeout          = 120
  memory_size      = 256

  environment {
    variables = {
      BUCKET = aws_s3_bucket.lake.bucket
    }
  }
}

output "ingest_lambda" {
  value = aws_lambda_function.ingest.function_name
}
