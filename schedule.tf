# Step 3.4: run the Step Functions pipeline on a daily schedule
# Same folder as the other .tf files.

# Created as DISABLED on purpose, so nothing runs (or costs money) until you decide.
# To switch it on, add this line to terraform.tfvars and run terraform apply:
#   schedule_state = "ENABLED"
variable "schedule_state" {
  default = "DISABLED"
}

# Role that lets the scheduler start our state machine, and nothing else
resource "aws_iam_role" "scheduler" {
  name = "olist-batch-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "olist-batch-scheduler-start-pipeline"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.pipeline.arn
    }]
  })
}

# Every day at 05:00 UTC (10:30 AM India time)
resource "aws_scheduler_schedule" "daily" {
  name                         = "olist-batch-daily"
  schedule_expression          = "cron(0 5 * * ? *)"
  schedule_expression_timezone = "UTC"
  state                        = var.schedule_state

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.pipeline.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})
  }
}
