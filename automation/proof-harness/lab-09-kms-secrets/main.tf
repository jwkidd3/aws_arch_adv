terraform {
  required_version = ">= 1.6"
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
      Lab       = "09-kms-secrets"
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

data "aws_caller_identity" "me" {}

# --- Customer-managed KMS key with kms:ViaService deny ---

resource "aws_kms_key" "lab" {
  description             = "archadv lab 9 harness key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIAMUserPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      # Deny direct kms:Decrypt when not coming via S3 (this is what Lab 9 Step 4 teaches).
      # NOTE: deliberately omitted in the harness because applying this deny breaks
      # Secrets Manager retrieval below — same cross-contamination the lab patch warns about.
      # The lab tells students to remove this deny before Part B; the harness simulates
      # that "removed" state to validate the rest of Part B.
    ]
  })
}

resource "aws_kms_alias" "lab" {
  name          = "alias/archadv-${var.harness_owner}-lab09"
  target_key_id = aws_kms_key.lab.key_id
}

# --- S3 bucket with default SSE-KMS using the CMK ---

resource "aws_s3_bucket" "secure" {
  bucket        = "archadv-${var.harness_owner}-lab09"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "secure" {
  bucket                  = aws_s3_bucket.secure.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secure" {
  bucket = aws_s3_bucket.secure.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.lab.arn
    }
    # Bucket Key disabled so encryption-context shape is the object ARN — same
    # state the lab requires for the kms:ViaService deny test.
    bucket_key_enabled = false
  }
}

resource "aws_s3_object" "secret_file" {
  bucket  = aws_s3_bucket.secure.id
  key     = "secret.txt"
  content = "harness-secret-payload"

  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.lab.arn
}

# --- Secrets Manager secret encrypted with the CMK ---

resource "aws_secretsmanager_secret" "db_pass" {
  name                    = "archadv-${var.harness_owner}-lab09-db-pass"
  kms_key_id              = aws_kms_key.lab.id
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_pass" {
  secret_id = aws_secretsmanager_secret.db_pass.id
  secret_string = jsonencode({
    username = "archadvuser"
    password = "harness-initial-pw-${random_string.suffix.result}"
  })
}

resource "random_string" "suffix" {
  length  = 12
  special = false
}
