
provider "aws" {
  region = "us-east-1"
}

resource "aws_kms_key" "data_key" {
  description             = "Key for encrypting S3 and RDS"
  deletion_window_in_days = 10
  enable_key_rotation      = true
}

resource "aws_kms_alias" "data_key_alias" {
  name          = "alias/data-key"
  target_key_id = aws_kms_key.data_key.id
}

resource "aws_s3_bucket" "secure_bucket" {
  bucket = "secure-data-bucket-example"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secure" {
  bucket = aws_s3_bucket.secure_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.data_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}
