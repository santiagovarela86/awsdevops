resource "aws_s3_bucket" "awsdemo-bucket" {
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
