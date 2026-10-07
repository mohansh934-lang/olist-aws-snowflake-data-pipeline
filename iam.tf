# Step 1.3: alerts + IAM roles for Lambda and Glue
# Goes in the same folder as main.tf (Terraform reads all .tf files together)

# ---------- Alerts ----------
resource "aws_sns_topic" "alerts" {
  name = "olist-batch-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------- Shared policy: read/write only inside our lake bucket ----------
resource "aws_iam_policy" "lake_rw" {
  name = "olist-batch-lake-rw"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.lake.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.lake.arn
      }
    ]
  })
}

# ---------- Roles ----------
locals {
  svc_roles = {
    lambda = {
      service = "lambda.amazonaws.com"
      managed = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    }
    glue = {
      service = "glue.amazonaws.com"
      managed = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
    }
  }
}

resource "aws_iam_role" "svc" {
  for_each = local.svc_roles
  name     = "olist-batch-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = each.value.service }
    }]
  })
}

# AWS-managed policy (logs for Lambda, Glue service basics)
resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = local.svc_roles
  role       = aws_iam_role.svc[each.key].name
  policy_arn = each.value.managed
}

# Our bucket access
resource "aws_iam_role_policy_attachment" "lake" {
  for_each   = local.svc_roles
  role       = aws_iam_role.svc[each.key].name
  policy_arn = aws_iam_policy.lake_rw.arn
}

output "lambda_role_arn" {
  value = aws_iam_role.svc["lambda"].arn
}

output "glue_role_arn" {
  value = aws_iam_role.svc["glue"].arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
