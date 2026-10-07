# Step 1.4: IAM role that Snowflake will assume to read silver/ and gold/
# Goes in the same folder as main.tf and iam.tf

# Leave these two empty for now. Fill them AFTER running DESC INTEGRATION in Snowflake.
variable "snowflake_iam_user_arn" {
  default = null
}

variable "snowflake_external_id" {
  default = "placeholder"
}

locals {
  snowflake_ready = var.snowflake_iam_user_arn != null
}

resource "aws_iam_role" "snowflake" {
  name = "olist-batch-snowflake"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        # Before Snowflake gives us its ARN, trust our own account (harmless placeholder)
        AWS = local.snowflake_ready ? var.snowflake_iam_user_arn : "arn:aws:iam::${data.aws_caller_identity.me.account_id}:root"
      }
      Condition = {
        StringEquals = { "sts:ExternalId" = var.snowflake_external_id }
      }
    }]
  })
}

# Read-only access to silver/ and gold/ (nothing else in the bucket)
resource "aws_iam_role_policy" "snowflake" {
  name = "olist-batch-snowflake-read"
  role = aws_iam_role.snowflake.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = ["${aws_s3_bucket.lake.arn}/gold/*", "${aws_s3_bucket.lake.arn}/silver/*"]
      },
      {
        Effect    = "Allow"
        Action    = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource  = aws_s3_bucket.lake.arn
        Condition = { StringLike = { "s3:prefix" = ["gold/*", "silver/*"] } }
      }
    ]
  })
}

output "snowflake_role_arn" {
  value = aws_iam_role.snowflake.arn
}
