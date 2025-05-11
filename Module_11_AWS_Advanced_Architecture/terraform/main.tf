
provider "aws" {
  region = "us-east-1"
}

resource "aws_lambda_function" "app_handler" {
  function_name = "large-scale-app"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = "arn:aws:iam::123456789012:role/lambda-role"

  filename = "lambda_function_payload.zip"
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "LargeScaleAPI"
  description = "API for large-scale application"
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = "myapp-alb.amazonaws.com"
    origin_id   = "app-alb"
  }

  enabled             = true
  default_root_object = ""
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "app-alb"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
