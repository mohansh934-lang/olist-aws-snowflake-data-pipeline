# Step 3.3B-2: Lambda that loads gold into Snowflake
# Same folder as the other .tf files. Needs lambda_snowflake_load.zip (made by build_lambda.sh).

# Add this line to terraform.tfvars:  snowflake_account = "<ORG-ACCOUNT>"
variable "snowflake_account" {
  type = string
}

# Upload the zip to S3 (too big to send directly). etag re-uploads it when the code changes.
resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.lake.id
  key    = "scripts/lambda_snowflake_load.zip"
  source = "${path.module}/lambda_snowflake_load.zip"
  source_hash = filemd5("${path.module}/lambda_snowflake_load.zip")
}

# The function. It reuses the olist-batch-lambda role we created in step 1.3.
resource "aws_lambda_function" "snowflake_load" {
  function_name    = "olist-batch-snowflake-load"
  role             = aws_iam_role.svc["lambda"].arn
  runtime          = "python3.12"
  handler          = "lambda_snowflake_load.handler"
  s3_bucket        = aws_s3_bucket.lake.id
  s3_key           = aws_s3_object.lambda_zip.key
  source_code_hash = filebase64sha256("${path.module}/lambda_snowflake_load.zip")
  timeout          = 180
  memory_size      = 512

  environment {
    variables = {
      SNOWFLAKE_ACCOUNT   = var.snowflake_account
      SNOWFLAKE_USER      = "OLIST_SVC"
      SNOWFLAKE_ROLE      = "OLIST_LOADER"
      SNOWFLAKE_WAREHOUSE = "OLIST_WH"
      KEY_PARAM           = "/olist/snowflake/private_key"
    }
  }
}

# Let the Lambda role read ONLY this one parameter. The key never passes through Terraform.
resource "aws_iam_role_policy" "lambda_read_key" {
  name = "olist-batch-lambda-read-snowflake-key"
  role = aws_iam_role.svc["lambda"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = "arn:aws:ssm:*:${data.aws_caller_identity.me.account_id}:parameter/olist/snowflake/private_key"
    }]
  })
}

output "snowflake_load_lambda" {
  value = aws_lambda_function.snowflake_load.function_name
}
