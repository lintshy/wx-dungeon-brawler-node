provider "aws" {
  region = var.aws_region
}

variable "aws_region" {}
variable "lambda_function_name" {}
variable "lambda_zip_path" {}
variable "environment" {}
variable "app_name" {}
variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default     = {}
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

# Lambda Execution Role
resource "aws_iam_role" "lambda_role" {
  name               = "dungeon-brawler-node-execution-role-${var.app_name}-${var.environment}"
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
  tags             = var.tags
}

# API Gateway
resource "aws_apigatewayv2_api" "dungeon_brawler" {
  name          = "${var.app_name}-api-gateway-${var.environment}"
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_integration" "dungeon_brawler" {
  api_id           = aws_apigatewayv2_api.dungeon_brawler.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.dungeon_brawler.invoke_arn
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.dungeon_brawler.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.dungeon_brawler.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.dungeon_brawler.id
  name        = "$default"
  auto_deploy = true
}
