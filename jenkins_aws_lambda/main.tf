resource "aws_dynamodb_table" "transactions_table" {
  name           = "transactions"
  billing_mode   = "PAY_PER_REQUEST" 
  hash_key       = "transaction_id"

  attribute {
    name = "transaction_id"
    type = "S" 
    
  }

  attribute {
    name = "status"
    type = "S" 
  }

    global_secondary_index {
    name               = "status-index"
    hash_key           = "status"
    projection_type    = "ALL" 
  }

  tags = {
    Environment = "Development"
    Project     = "PendingTransactions"
  }
}

resource "aws_lambda_function" "query_transactions" {
  function_name = "query_transactions"
  role          = aws_iam_role.lambda_execution_role.arn
  runtime       = "python3.9"
  handler       = "lambda_function.lambda_handler"
  filename      = "lambda_function.zip" # Archivo con el código Lambda

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.transactions_table.name
    }
  }
}

## eventos ###



### role ###

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}





resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda_dynamodb_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["dynamodb:Query", "dynamodb:Scan"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.transactions_table.arn
      }
    ]
  })
}


resource "aws_cloudwatch_event_rule" "query_schedule" {
  name        = "query_transactions_schedule"
  description = "Ejecuta la Lambda para consultar transacciones pendientes"
  schedule_expression = "rate(5 minutes)" # Ejecutar cada 5 minutos
}

resource "aws_cloudwatch_event_target" "query_target" {
  rule      = aws_cloudwatch_event_rule.query_schedule.name
  arn       = aws_lambda_function.query_transactions.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query_transactions.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.query_schedule.arn
}




### cloud watch para revisar las transacciones fallidas
resource "aws_cloudwatch_metric_alarm" "failed_transactions_alarm" {
  alarm_name          = "FailedTransactionsAlarm"
  metric_name         = "ProcessedTransactions"
  namespace           = "TransactionProcessing"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  alarm_description   = "Alarma cuando las transacciones fallidas superan el umbral."

  dimensions = {
    Success = "False"
  }

  alarm_actions = ["arn:aws:sns:us-east-1:123456789012:MyTopic"]
}