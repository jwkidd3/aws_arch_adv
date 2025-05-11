
provider "aws" {
  region = "us-east-1"
}

resource "aws_db_instance" "migrated_db" {
  identifier         = "migrated-db"
  instance_class     = "db.t3.micro"
  engine             = "mysql"
  username           = "admin"
  password           = "password123!"
  allocated_storage  = 20
  skip_final_snapshot = true
}

resource "aws_iam_role" "dms_role" {
  name = "dms-vpc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "dms.amazonaws.com"
      }
    }]
  })
}
