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
        Resource = "${aws_sqs_queue.awsdemo-sqs.arn}"
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
    deadLetterTargetArn = "${aws_sqs_queue.awsdemo-sqs-deadletter.arn}"
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
        Resource = "${aws_dynamodb_table.awsdemo-dynamodb-table.arn}"
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
          "sqs:DeleteMessage"
        ]
        Effect   = "Allow"
        Resource = "${aws_sqs_queue.awsdemo-sqs.arn}"
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
