provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "dev"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::962804303520:role/automation"
  }
}

provider "aws" {
  alias  = "staging"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::714223118628:role/automation"
  }
}

provider "aws" {
  alias  = "prod"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::072853782546:role/automation"
  }
}

data "aws_caller_identity" "dev" {
  provider = aws.dev
}

data "aws_caller_identity" "staging" {
  provider = aws.staging
}

data "aws_caller_identity" "prod" {
  provider = aws.prod
}

output "caller_identities" {
  value = {
    dev     = data.aws_caller_identity.dev.arn
    staging = data.aws_caller_identity.staging.arn
    prod    = data.aws_caller_identity.prod.arn
  }
}
