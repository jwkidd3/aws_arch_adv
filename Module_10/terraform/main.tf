terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "learner" {
  description = "Learner-unique resource prefix (e.g. first name)"
  type        = string
}

locals {
  common_tags = {
    Owner  = var.learner
    Course = "archadv"
    Module = "10"
  }
  bucket_name = "archadv-${var.learner}-datalake"
  results_bucket_name = "archadv-${var.learner}-athena-results"
  db_name = "archadv_${var.learner}_db"
}

# --- S3 data lake bucket ----------------------------------------------------

resource "aws_s3_bucket" "lake" {
  bucket        = local.bucket_name
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# Seed two CSVs under sales/year=2024/ so the crawler has data to find.

resource "aws_s3_object" "seed_1" {
  bucket  = aws_s3_bucket.lake.id
  key     = "sales/year=2024/q1.csv"
  content = <<-CSV
    order_id,region,product,quantity,revenue
    1001,us-east,widget-a,3,29.97
    1002,us-east,widget-b,1,49.99
    1003,us-west,widget-a,5,49.95
    1004,eu-west,widget-c,2,79.98
    1005,ap-south,widget-b,4,199.96
  CSV
  content_type = "text/csv"
  tags         = local.common_tags
}

resource "aws_s3_object" "seed_2" {
  bucket  = aws_s3_bucket.lake.id
  key     = "sales/year=2024/q2.csv"
  content = <<-CSV
    order_id,region,product,quantity,revenue
    2001,us-east,widget-a,7,69.93
    2002,us-west,widget-c,3,119.97
    2003,us-west,widget-b,2,99.98
    2004,eu-west,widget-a,4,39.96
    2005,ap-south,widget-c,1,39.99
  CSV
  content_type = "text/csv"
  tags         = local.common_tags
}

# --- Glue catalog + crawler --------------------------------------------------

resource "aws_glue_catalog_database" "lake" {
  name = local.db_name
}

resource "aws_iam_role" "glue" {
  name = "archadv-${var.learner}-glue-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_read" {
  name = "lake-s3-read"
  role = aws_iam_role.glue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.lake.arn, "${aws_s3_bucket.lake.arn}/*"]
    }]
  })
}

resource "aws_glue_crawler" "sales" {
  name          = "archadv-${var.learner}-sales-crawler"
  database_name = aws_glue_catalog_database.lake.name
  role          = aws_iam_role.glue.arn

  s3_target {
    path = "s3://${aws_s3_bucket.lake.bucket}/sales/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = local.common_tags
}

# --- Athena results bucket + workgroup --------------------------------------

resource "aws_s3_bucket" "athena_results" {
  bucket        = local.results_bucket_name
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_athena_workgroup" "lab" {
  name = "archadv-${var.learner}-wg"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"
    }
  }

  force_destroy = true
  tags          = local.common_tags
}

# --- Outputs ----------------------------------------------------------------

output "lake_bucket"        { value = aws_s3_bucket.lake.bucket }
output "athena_workgroup"   { value = aws_athena_workgroup.lab.name }
output "glue_database"      { value = aws_glue_catalog_database.lake.name }
output "glue_crawler"       { value = aws_glue_crawler.sales.name }
