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
  #source_account "SourceAccount: !Ref AWS::AccountId"
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

# resource "aws_api_gateway_rest_api" "awsdemo-apigateway-api" {
#   name        = "awsdemo-apigateway-api"
#   description = "AWS DEMO Api Gateway"
# }

# resource "aws_api_gateway_resource" "awsdemo-apigateway-resource-getmessage" {
#   rest_api_id = aws_api_gateway_rest_api.awsdemo-apigateway-api.id
#   parent_id   = aws_api_gateway_rest_api.awsdemo-apigateway-api.root_resource_id
#   path_part   = "message"
# }

# resource "aws_api_gateway_resource" "awsdemo-apigateway-resource-getmessages" {
#   rest_api_id = aws_api_gateway_rest_api.awsdemo-apigateway-api.id
#   parent_id   = aws_api_gateway_rest_api.awsdemo-apigateway-api.root_resource_id
#   path_part   = "message/{date}"
# }

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

# resource "aws_api_gateway_method" "awsdemo-apigateway-get" {
#   rest_api_id   = aws_api_gateway_rest_api.awsdemo-apigateway-api.id
#   resource_id   = aws_api_gateway_resource.awsdemo-apigateway-resource.id
#   http_method   = "GET"
#   authorization = "NONE"
# }

# # resource "aws_api_gateway_method" "awsdemo-apigateway-post" {
# #   rest_api_id   = aws_api_gateway_rest_api.awsdemo-apigateway-api.id
# #   resource_id   = aws_api_gateway_resource.awsdemo-apigateway-resource.id
# #   http_method   = "POST"
# #   authorization = "NONE"
# # }

# # resource "aws_api_gateway_method" "awsdemo-apigateway-put" {
# #   rest_api_id   = aws_api_gateway_rest_api.awsdemo-apigateway-api.id
# #   resource_id   = aws_api_gateway_resource.awsdemo-apigateway-resource.id
# #   http_method   = "PUT"
# #   authorization = "NONE"
# # }

# # resource "aws_api_gateway_method" "awsdemo-apigateway-delete" {
# #   rest_api_id   = aws_api_gateway_rest_api.awsdemo-apigateway-api.id
# #   resource_id   = aws_api_gateway_resource.awsdemo-apigateway-resource.id
# #   http_method   = "DELETE"
# #   authorization = "NONE"
# # }

# resource "aws_iam_role" "iam-apigateway-serverless" {
#   name = "iam-apigateway-serverless"

#   assume_role_policy = <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Action": "sts:AssumeRole",
#       "Principal": {
#         "Service": "lambda.amazonaws.com"
#       },
#       "Effect": "Allow",
#       "Sid": ""
#     }
#   ]
# }
# EOF

#   managed_policy_arns = [aws_iam_policy.dynamodb.arn]

#   tags = {
#     Environment = "AWS-Demo"
#   }
# }

# resource "aws_lambda_function" "awsdemo-getmessages" {
#   filename         = "lambda_apigtw_to_dynamodb.zip"
#   function_name    = "awsdemo-getmessages"
#   handler          = "app.getMessages"
#   role             = aws_iam_role.iam-apigateway-serverless.arn
#   source_code_hash = filebase64sha256("lambda_apigtw_to_dynamodb.zip")
#   runtime          = "nodejs10.x"
#   description      = "Get all messages in DynamoDB table (scan)"

#   tags = {
#     Environment = "AWS-Demo"
#   }
# }

# resource "aws_lambda_function" "awsdemo-getmessage" {
#   filename         = "lambda_apigtw_to_dynamodb.zip"
#   function_name    = "awsdemo-getmessage"
#   handler          = "app.getMessage"
#   role             = aws_iam_role.iam-apigateway-serverless.arn
#   source_code_hash = filebase64sha256("lambda_apigtw_to_dynamodb.zip")
#   runtime          = "nodejs10.x"
#   description      = "Get single message based on timestamp and location"

#   tags = {
#     Environment = "AWS-Demo"
#   }
# }

# resource "aws_api_gateway_integration" "awsdemo-integration-getmessages" {
#   rest_api_id = aws_api_gateway_rest_api.awsdemo-apigateway-api.id
#   resource_id = aws_api_gateway_method.awsdemo-apigateway-get.resource_id
#   http_method = aws_api_gateway_method.awsdemo-apigateway-get.http_method

#   integration_http_method = "GET"
#   type                    = "AWS_PROXY"
#   uri                     = aws_lambda_function.awsdemo-getmessages.invoke_arn
# }

# resource "aws_api_gateway_integration" "awsdemo-integration-getmessage" {
#   rest_api_id = aws_api_gateway_rest_api.awsdemo-apigateway-api.id
#   resource_id = aws_api_gateway_method.awsdemo-apigateway-get.resource_id
#   http_method = aws_api_gateway_method.awsdemo-apigateway-get.http_method

#   integration_http_method = "GET"
#   type                    = "AWS_PROXY"
#   uri                     = aws_lambda_function.awsdemo-getmessage.invoke_arn
# }
