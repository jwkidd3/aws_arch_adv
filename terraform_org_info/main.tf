# Root module (main.tf)

# Default AWS provider configuration (e.g., us-east-1)
provider "aws" {
  region = "us-east-1"
}

# AWS provider configuration with an alias for us-west-2
provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

# Module to create an S3 bucket
module "west_region_bucket" {
  source = "./modules/account_info"
  providers = {
    aws = aws.west
  }
  bucket_name = "my-west-region-bucket"
}

# Module to create another S3 bucket in the default region
module "default_region_bucket" {
  source = "./modules/account_info"
  bucket_name = "my-default-region-bucket"
}


