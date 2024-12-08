provider "aws" {
  region = var.aws_region
}

variable "aws_region" {}
variable "lambda_function_name" {}
variable "lambda_zip_path" {}

# Lambda Function
resource "aws_lambda_function" "dungeon_brawler" {
  function_name    = var.lambda_function_name
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  role             = aws_iam_role.lambda_role.arn
  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)
}

# Lambda Execution Role
resource "aws_iam_role" "lambda_role" {
  name               = "lambda-execution-role"
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
}

# Attach Policy to Role
resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda-policy"
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

# API Gateway
resource "aws_apigatewayv2_api" "dungeon_brawler" {
  name          = "dungeon_brawler-api"
  protocol_type = "HTTP"
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
