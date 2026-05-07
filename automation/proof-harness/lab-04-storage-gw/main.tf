terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Course    = "archadv"
      Owner     = var.harness_owner
      ManagedBy = "proof-harness"
      Lab       = "04-storage-gw"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "harness_owner" {
  type    = string
  default = "ci"
}

# Lab 4 harness validates that the AMIs and managed policies the lab guide
# depends on still resolve. Actual EC2 launches and gateway activation are
# skipped — they cost ~$0.20/run and the activation handshake is awkward
# to script. Instructor dry-run covers the launch/activation path.

# --- AMI resolution checks ---

data "aws_ami" "storage_gateway" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["aws-storage-gateway-*"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "datasync" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["aws-datasync-*"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

# --- Destination bucket for the file gateway / DataSync ---

resource "aws_s3_bucket" "filegw" {
  bucket        = "archadv-${var.harness_owner}-lab04-filegw"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "filegw" {
  bucket                  = aws_s3_bucket.filegw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "filegw" {
  bucket = aws_s3_bucket.filegw.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# --- IAM role for Storage Gateway service ---

resource "aws_iam_role" "storage_gateway" {
  name = "archadv-${var.harness_owner}-lab04-sgw"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "storagegateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "storage_gateway_s3" {
  name = "lab04-sgw-s3"
  role = aws_iam_role.storage_gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject", "s3:PutObject", "s3:ListBucket",
        "s3:DeleteObject", "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads", "s3:AbortMultipartUpload"
      ]
      Resource = [aws_s3_bucket.filegw.arn, "${aws_s3_bucket.filegw.arn}/*"]
    }]
  })
}

# --- Quota probe: can this region launch m5.2xlarge (DataSync minimum)? ---

data "aws_ec2_instance_type_offerings" "datasync_min" {
  filter {
    name   = "instance-type"
    values = ["m5.2xlarge"]
  }
  filter {
    name   = "location"
    values = [var.region]
  }
  location_type = "region"
}
