# DevOps Playground Repo (AWS Version)

I've created this repository to try out multiple DevOps/AWS tools at once such as CircleCI, Terraform, S3, Lambda, SQS, DynamoDB, API Gateway, etc.

The idea is to deploy both the infrastructure and the code of a test application to the Cloud using entirely Source Control (git).

The application's architecture is event-driven and serverless.

Based on the following blog post -> https://programmaticponderings.com/2019/10/04/event-driven-serverless-architectures-with-aws-lambda-sqs-dynamodb-and-api-gateway/

Link to the original repo -> https://github.com/garystafford/serverless-sqs-dynamo-demo

Terraform state is kept in a separate S3 bucket.