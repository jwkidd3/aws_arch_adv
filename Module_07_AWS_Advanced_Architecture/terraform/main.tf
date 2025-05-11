
provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "ci_cd_bucket" {
  bucket = "ci-cd-bucket-example-123"
  force_destroy = true

  tags = {
    Name = "CI/CD Bucket"
  }
}
