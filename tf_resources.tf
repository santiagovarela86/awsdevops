resource "aws_s3_bucket" "awsdemo-bucket" {
  bucket = "s3-bucket-demo-devops"
  acl    = "private"

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_iam_role" "iam_s3_to_sqs" {
  name = "iam_s3_to_sqs"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  managed_policy_arns = [aws_iam_policy.logging.arn, aws_iam_policy.getObjects.arn, aws_iam_policy.produceToQueue.arn]

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_iam_policy" "logging" {
  name = "allowLogging"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["logs:*"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_policy" "getObjects" {
  name = "getObjects"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:GetObject"]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.awsdemo-bucket.arn}/*"
      },
    ]
  })
}

resource "aws_iam_policy" "produceToQueue" {
  name = "produceToQueue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["sqs:SendMessage"]
        Effect   = "Allow"
        Resource = aws_sqs_queue.awsdemo-sqs.arn
      },
    ]
  })
}

resource "aws_lambda_function" "awsdemo-s3-to-sqs" {
  filename         = "lambda_s3_to_sqs.zip"
  function_name    = "awsdemo-s3-to-sqs"
  handler          = "app.lambda_handler"
  role             = aws_iam_role.iam_s3_to_sqs.arn
  source_code_hash = filebase64sha256("lambda_s3_to_sqs.zip")
  runtime          = "python3.7"
  description      = "Responds to S3 Event - Sends to SQS"

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_lambda_permission" "awsdemo-allow-bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.awsdemo-s3-to-sqs.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.awsdemo-bucket.arn
}

resource "aws_s3_bucket_notification" "awsdemo-s3-to-sqs-notification" {
  bucket = aws_s3_bucket.awsdemo-bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.awsdemo-s3-to-sqs.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.awsdemo-allow-bucket]
}

resource "aws_sqs_queue" "awsdemo-sqs-deadletter" {
  name = "awsdemo-sqs-deadletter"

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_sqs_queue" "awsdemo-sqs" {
  name = "awsdemo-sqs"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.awsdemo-sqs-deadletter.arn
    maxReceiveCount     = 5
  })

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_dynamodb_table" "awsdemo-dynamodb-table" {
  name           = "awsdemo-dynamodb-table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 25
  write_capacity = 25
  hash_key       = "date"
  range_key      = "time"

  attribute {
    name = "date"
    type = "S"
  }

  attribute {
    name = "time"
    type = "S"
  }

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_iam_role" "iam_sqs_to_dynamodb" {
  name = "iam_sqs_to_dynamodb"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  managed_policy_arns = [aws_iam_policy.dynamodb.arn, aws_iam_policy.receiveFromQueue.arn]

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_iam_policy" "dynamodb" {
  name = "dynamodb"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
              "dynamodb:GetItem",
              "dynamodb:DeleteItem",
              "dynamodb:PutItem",
              "dynamodb:Scan",
              "dynamodb:Query",
              "dynamodb:UpdateItem",
              "dynamodb:BatchWriteItem",
              "dynamodb:BatchGetItem",
              "dynamodb:DescribeTable",
              "dynamodb:ConditionCheckItem"
            ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.awsdemo-dynamodb-table.arn
      },
    ]
  })
}

resource "aws_iam_policy" "receiveFromQueue" {
  name = "receiveFromQueue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.awsdemo-sqs.arn
      },
    ]
  })
}

resource "aws_lambda_function" "awsdemo-sqs-to-dynamodb" {
  filename         = "lambda_sqs_to_dynamodb.zip"
  function_name    = "awsdemo-sqs-to-dynamodb"
  handler          = "app.lambda_handler"
  role             = aws_iam_role.iam_sqs_to_dynamodb.arn
  source_code_hash = filebase64sha256("lambda_sqs_to_dynamodb.zip")
  runtime          = "python3.7"
  description      = "Responds to SQS Event - Sends to Dynamodb"

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_lambda_event_source_mapping" "awsdemo-sqs-to-dynamodb-event" {
  event_source_arn = aws_sqs_queue.awsdemo-sqs.arn
  function_name    = aws_lambda_function.awsdemo-sqs-to-dynamodb.arn
  batch_size       = 10
  enabled          = true
}

resource "aws_api_gateway_rest_api" "awsdemo-apigateway" {
  name        = "awsdemo-apigateway"
  description = "AWS DEMO Api Gateway"
}

resource "aws_api_gateway_resource" "awsdemo-message" {
  rest_api_id = aws_api_gateway_rest_api.awsdemo-apigateway.id
  parent_id   = aws_api_gateway_rest_api.awsdemo-apigateway.root_resource_id
  path_part   = "message"
}

resource "aws_api_gateway_method" "awsdemo-getMessages" {
  rest_api_id   = aws_api_gateway_rest_api.awsdemo-apigateway.id
  resource_id   = aws_api_gateway_resource.awsdemo-message.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "awsdemo-postMessage" {
  rest_api_id   = aws_api_gateway_rest_api.awsdemo-apigateway.id
  resource_id   = aws_api_gateway_resource.awsdemo-message.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_resource" "awsdemo-message-date" {
  rest_api_id = aws_api_gateway_rest_api.awsdemo-apigateway.id
  parent_id   = aws_api_gateway_resource.awsdemo-message.id
  path_part   = "{date}"
}

resource "aws_api_gateway_method" "awsdemo-getMessage" {
  rest_api_id   = aws_api_gateway_rest_api.awsdemo-apigateway.id
  resource_id   = aws_api_gateway_resource.awsdemo-message-date.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "awsdemo-putMessage" {
  rest_api_id   = aws_api_gateway_rest_api.awsdemo-apigateway.id
  resource_id   = aws_api_gateway_resource.awsdemo-message-date.id
  http_method   = "PUT"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "awsdemo-deleteMessage" {
  rest_api_id   = aws_api_gateway_rest_api.awsdemo-apigateway.id
  resource_id   = aws_api_gateway_resource.awsdemo-message-date.id
  http_method   = "DELETE"
  authorization = "NONE"
}

resource "aws_iam_role" "iam-apigateway-serverless" {
  name = "iam-apigateway-serverless"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  managed_policy_arns = [aws_iam_policy.dynamodb.arn]

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_lambda_function" "awsdemo-getMessages" {
  filename         = "lambda_apigtw_to_dynamodb.zip"
  function_name    = "awsdemo-getMessages"
  handler          = "app.getMessages"
  role             = aws_iam_role.iam-apigateway-serverless.arn
  source_code_hash = filebase64sha256("lambda_apigtw_to_dynamodb.zip")
  runtime          = "nodejs12.x"
  description      = "Get all messages in DynamoDB table (scan)"

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_lambda_function" "awsdemo-postMessage" {
  filename         = "lambda_apigtw_to_dynamodb.zip"
  function_name    = "awsdemo-postMessage"
  handler          = "app.postMessage"
  role             = aws_iam_role.iam-apigateway-serverless.arn
  source_code_hash = filebase64sha256("lambda_apigtw_to_dynamodb.zip")
  runtime          = "nodejs12.x"
  description      = "Create new message item in DynamoDB table"

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_lambda_function" "awsdemo-getMessage" {
  filename         = "lambda_apigtw_to_dynamodb.zip"
  function_name    = "awsdemo-getMessage"
  handler          = "app.getMessage"
  role             = aws_iam_role.iam-apigateway-serverless.arn
  source_code_hash = filebase64sha256("lambda_apigtw_to_dynamodb.zip")
  runtime          = "nodejs12.x"
  description      = "Get single message based on timestamp and location"

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_lambda_function" "awsdemo-putMessage" {
  filename         = "lambda_apigtw_to_dynamodb.zip"
  function_name    = "awsdemo-putMessage"
  handler          = "app.putMessage"
  role             = aws_iam_role.iam-apigateway-serverless.arn
  source_code_hash = filebase64sha256("lambda_apigtw_to_dynamodb.zip")
  runtime          = "nodejs12.x"
  description      = "Update message item in DynamoDB table"

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_lambda_function" "awsdemo-deleteMessage" {
  filename         = "lambda_apigtw_to_dynamodb.zip"
  function_name    = "awsdemo-deleteMessage"
  handler          = "app.deleteMessage"
  role             = aws_iam_role.iam-apigateway-serverless.arn
  source_code_hash = filebase64sha256("lambda_apigtw_to_dynamodb.zip")
  runtime          = "nodejs12.x"
  description      = "Delete message item in DynamoDB table"

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_lambda_permission" "awsdemo-getMessages" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.awsdemo-getMessages.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.awsdemo-apigateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "awsdemo-postMessage" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.awsdemo-postMessage.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.awsdemo-apigateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "awsdemo-getMessage" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.awsdemo-getMessage.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.awsdemo-apigateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "awsdemo-putMessage" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.awsdemo-putMessage.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.awsdemo-apigateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "awsdemo-deleteMessage" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.awsdemo-deleteMessage.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.awsdemo-apigateway.execution_arn}/*/*"
}

resource "aws_api_gateway_integration" "awsdemo-getMessages" {
  rest_api_id             = aws_api_gateway_rest_api.awsdemo-apigateway.id
  resource_id             = aws_api_gateway_method.awsdemo-getMessages.resource_id
  http_method             = aws_api_gateway_method.awsdemo-getMessages.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.awsdemo-getMessages.invoke_arn
}

resource "aws_api_gateway_integration" "awsdemo-postMessage" {
  rest_api_id             = aws_api_gateway_rest_api.awsdemo-apigateway.id
  resource_id             = aws_api_gateway_method.awsdemo-postMessage.resource_id
  http_method             = aws_api_gateway_method.awsdemo-postMessage.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.awsdemo-postMessage.invoke_arn
}

resource "aws_api_gateway_integration" "awsdemo-getMessage" {
  rest_api_id             = aws_api_gateway_rest_api.awsdemo-apigateway.id
  resource_id             = aws_api_gateway_method.awsdemo-getMessage.resource_id
  http_method             = aws_api_gateway_method.awsdemo-getMessage.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.awsdemo-getMessage.invoke_arn
}

resource "aws_api_gateway_integration" "awsdemo-putMessage" {
  rest_api_id             = aws_api_gateway_rest_api.awsdemo-apigateway.id
  resource_id             = aws_api_gateway_method.awsdemo-putMessage.resource_id
  http_method             = aws_api_gateway_method.awsdemo-putMessage.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.awsdemo-putMessage.invoke_arn
}

resource "aws_api_gateway_integration" "awsdemo-deleteMessage" {
  rest_api_id             = aws_api_gateway_rest_api.awsdemo-apigateway.id
  resource_id             = aws_api_gateway_method.awsdemo-deleteMessage.resource_id
  http_method             = aws_api_gateway_method.awsdemo-deleteMessage.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.awsdemo-deleteMessage.invoke_arn
}

resource "aws_api_gateway_deployment" "awsdemo-deployment" {
  rest_api_id = aws_api_gateway_rest_api.awsdemo-apigateway.id
}

resource "aws_api_gateway_stage" "awsdemo-stage" {
  deployment_id = aws_api_gateway_deployment.awsdemo-deployment.id
  rest_api_id   = aws_api_gateway_rest_api.awsdemo-apigateway.id
  stage_name    = "Prod"

  tags = {
    Environment = "AWS-Demo"
  }
}

# resource "aws_api_gateway_api_key" "awsdemo-apigateway-apikey" {
#   name = "awsdemo-apigateway-apikey"
# }

# resource "aws_api_gateway_deployment" "awsdemo-apigateway-deployment" {
#   rest_api_id = aws_api_gateway_rest_api.awsdemo-apigateway-api.id

#   depends_on = [aws_api_gateway_integration.awsdemo-integration-getmessage, aws_api_gateway_integration.awsdemo-integration-getmessages]
# }

# resource "aws_api_gateway_stage" "awsdemo-apigateway-stage" {
#   deployment_id = aws_api_gateway_deployment.awsdemo-apigateway-deployment.id
#   rest_api_id   = aws_api_gateway_rest_api.awsdemo-apigateway-api.id
#   stage_name    = "Prod"

#   tags = {
#     Environment = "AWS-Demo"
#   }
# }

# resource "aws_api_gateway_usage_plan" "awsdemo-apigateway-usageplan" {
#   name         = "awsdemo-apigateway-usageplan"

#   api_stages {
#     api_id = aws_api_gateway_rest_api.awsdemo-apigateway-api.id
#     stage  = aws_api_gateway_stage.awsdemo-apigateway-stage.stage_name
#   }

#   quota_settings {
#     limit  = 5000
#     period = "MONTH"
#   }

#   throttle_settings {
#     burst_limit = 200
#     rate_limit  = 100
#   }

#   tags = {
#     Environment = "AWS-Demo"
#   }
# }

# resource "aws_api_gateway_usage_plan_key" "awsdemo-apigateway-usageplankey" {
#   key_id        = aws_api_gateway_api_key.awsdemo-apigateway-apikey.id
#   key_type      = "API_KEY"
#   usage_plan_id = aws_api_gateway_usage_plan.awsdemo-apigateway-usageplan.id
# }
