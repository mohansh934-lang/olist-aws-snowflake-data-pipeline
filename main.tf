terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "alert_email" {
  type = string
}

provider "aws" {
  region = "eu-west-1"
}

data "aws_caller_identity" "me" {}

locals {
  bucket = "olist-batch-lake-eu-eu-${data.aws_caller_identity.me.account_id}"
}

# S3 bucket for the data lake
resource "aws_s3_bucket" "lake" {
  bucket = local.bucket
}

# Keep the bucket fully private
resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Folder-like prefixes: raw -> silver -> gold
resource "aws_s3_object" "prefixes" {
  for_each = toset(["raw/", "silver/", "gold/", "scripts/"])
  bucket   = aws_s3_bucket.lake.id
  key      = each.value
  content  = ""
}

# Email alert at 80% of a $5 monthly budget
resource "aws_budgets_budget" "monthly" {
  name         = "olist-batch-monthly"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

output "bucket" {
  value = aws_s3_bucket.lake.bucket
}
