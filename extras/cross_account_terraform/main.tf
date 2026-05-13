provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias      = "assume_account_b"
  region     = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::962804303520:role/automation"
  }
}

data "aws_caller_identity" "whoami" {
  provider = aws.assume_account_b
}

output "test"{
  value=data.aws_caller_identity.whoami.user_id
}