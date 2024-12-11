provider "aws" {
  region = var.aws_region
}

variable "aws_region" {}
variable "lambda_function_name" {}
variable "terraform_state_bucket_name" {}
variable "terraform_lock_table_name" {}
variable "lambda_zip_path" {}
variable "environment" {}
variable "app_name" {}
variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default     = {}
}

# Create an S3 bucket for Terraform state
resource "aws_s3_bucket" "dungeon_brawler" {
  bucket = var.s3_bucket_name
  acl    = "private"

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = var.tags
}

# Create a DynamoDB table for state locking
resource "aws_dynamodb_table" "dungeon_brawler_db_users" {
  name           = var.dynamodb_users_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  tags = var.tags
}


# Lambda Execution Role
resource "aws_iam_role" "lambda_role" {
  name               = "${var.app_name}-node-execution-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })
  tags             = var.tags
}

# Lambda Function
resource "aws_lambda_function" "dungeon_brawler" {
  function_name    = var.lambda_function_name
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  role             = aws_iam_role.lambda_role.arn
  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  tags             = var.tags
}

# Attach Policy to Role
resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda-policy-${var.app_name}-${var.environment}"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
# Create API Gateway REST API
resource "aws_api_gateway_rest_api" "dungeon_brawler" {
  name        = "${var.app_name}-api"
  description = "API for ${var.app_ name}"
  tags        = var.tags
}

# Create API Gateway Resource (e.g., '/resource')
resource "aws_api_gateway_resource" "dungeon_brawler_resource" {
  rest_api_id = aws_api_gateway_rest_api.dungeon_brawler.id
  parent_id   = aws_api_gateway_rest_api.dungeon_brawler.root_resource_id
  path_part   = "resource"
}

# Create API Gateway Method (e.g., GET)
resource "aws_api_gateway_method" "dungeon_brawler_method" {
  rest_api_id   = aws_api_gateway_rest_api.dungeon_brawler.id
  resource_id   = aws_api_gateway_resource.dungeon_brawler_resource.id
  http_method   = "GET"  # You can use other methods like POST, PUT, etc.
  authorization = "NONE" # or use AWS_IAM, Cognito, etc. for authorization
}

# Create API Gateway Lambda Integration
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.dungeon_brawler.id
  resource_id             = aws_api_gateway_resource.dungeon_brawler_resource.id
  http_method             = aws_api_gateway_method.dungeon_brawler_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"  # Use "AWS_PROXY" for Lambda integration
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.dungeon_brawler.arn}/invocations"
}

# Grant API Gateway permissions to invoke Lambda function
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dungeon_brawler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.dungeon_brawler.execution_arn}/*/*"
}

# Deploy API Gateway
resource "aws_api_gateway_deployment" "dungeon_brawler_deployment" {
  rest_api_id = aws_api_gateway_rest_api.dungeon_brawler.id
  stage_name  = "prod"

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}

terraform {
  backend "s3" {
    bucket         = "dungeon-brawler-iac-bucket"
    key            = "terraform/global/dungeon_brawler.tfstate"
    region         = "us-east-1"
    dynamodb_table = "dungeon-brawler-iac-lock"
    encrypt        = true
  }
}
