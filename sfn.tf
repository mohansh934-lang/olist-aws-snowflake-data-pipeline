# Step 3.2 + 3.5: Step Functions pipeline:
# ingest -> silver job -> gold job -> Snowflake load, SNS email on any failure
# Goes in the same folder as the other .tf files.

# ---------- Role that Step Functions uses ----------
resource "aws_iam_role" "sfn" {
  name = "olist-batch-sfn"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn" {
  name = "olist-batch-sfn-policy"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Start and watch only our own Glue jobs (names starting with olist-)
        Effect   = "Allow"
        Action   = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
        Resource = "arn:aws:glue:*:${data.aws_caller_identity.me.account_id}:job/olist-*"
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      },
      {
        # Both Lambdas: the new ingest one and the Snowflake load one
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          aws_lambda_function.ingest.arn,
          aws_lambda_function.snowflake_load.arn,
        ]
      }
    ]
  })
}

# ---------- The pipeline (a flowchart written as JSON) ----------
# The date travels through the whole run as {"ingest_date": "YYYY-MM-DD"}.
# Normal daily run: input is {}, the ingest Lambda picks today's date.
# Re-run an old day: start the execution with {"ingest_date": "2026-10-02"}.
resource "aws_sfn_state_machine" "pipeline" {
  name     = "olist-batch-pipeline"
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"

  definition = jsonencode({
    Comment = "Olist batch pipeline: ingest -> raw -> silver -> gold -> Snowflake"
    StartAt = "Ingest"
    States = {
      Ingest = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.ingest.arn
          "Payload.$"  = "$" # passes the execution input, so an old date can be re-run
        }
        # Keep only the date from the Lambda result; it becomes the new state: {"ingest_date": "..."}
        ResultSelector = {
          "ingest_date.$" = "$.Payload.ingest_date"
        }
        ResultPath = "$"
        Next       = "RawToSilver"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "NotifyFailure"
        }]
      }

      RawToSilver = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync" # .sync = wait until the job finishes
        Parameters = {
          JobName = "olist-raw-to-silver"
          Arguments = {
            "--INGEST_DATE.$" = "$.ingest_date" # this script expects CAPITAL letters
          }
        }
        ResultPath = null
        Next       = "SilverToGold"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "NotifyFailure"
        }]
      }

      SilverToGold = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.silver_to_gold.name
          Arguments = {
            "--ingest_date.$" = "$.ingest_date" # this script expects small letters
          }
        }
        ResultPath = null
        Next       = "LoadSnowflake"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "NotifyFailure"
        }]
      }

      LoadSnowflake = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.snowflake_load.arn
          Payload      = {}
        }
        ResultPath = null
        # The load empties and refills the tables, so trying again is safe
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 30
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Next = "Done"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "NotifyFailure"
        }]
      }

      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.alerts.arn
          Subject     = "Olist pipeline FAILED"
          "Message.$" = "States.JsonToString($.error)"
        }
        Next = "PipelineFailed"
      }

      PipelineFailed = {
        Type  = "Fail"
        Error = "PipelineFailed"
        Cause = "A step failed, see the alert email and the execution graph"
      }

      Done = {
        Type = "Succeed"
      }
    }
  })
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}
