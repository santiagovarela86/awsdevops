resource "aws_s3_bucket" "awsdemo" {
  bucket = "s3-bucket-demo-devops"
  acl    = "private"

  tags = {
    Environment = "AWS-Demo"
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

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
}

resource "aws_lambda_function" "awsdemo-s3-to-sqs" {
  filename         = "lambda_s3_to_sqs.zip"
  function_name    = "awsdemo-s3-to-sqs"
  handler          = "app.lambda_handler"
  role             = aws_iam_role.iam_for_lambda.arn
  source_code_hash = filebase64sha256("lambda_s3_to_sqs.zip")
  runtime          = "python3.7"

  tags = {
    Environment = "AWS-Demo"
  }
}
