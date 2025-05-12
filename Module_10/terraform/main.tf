
provider "aws" {
  region = "us-east-1"
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "aurora-cluster"
  engine                  = "aurora-mysql"
  master_username         = "admin"
  master_password         = "examplepass123"
  skip_final_snapshot     = true
}

resource "aws_rds_cluster_instance" "aurora_instance" {
  identifier              = "aurora-instance-1"
  cluster_identifier      = aws_rds_cluster.aurora.id
  instance_class          = "db.r5.large"
  engine                  = aws_rds_cluster.aurora.engine
}

resource "aws_dynamodb_table" "data_table" {
  name         = "LargeScaleData"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  ttl {
    attribute_name = "expire_at"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }
}
