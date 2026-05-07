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
    Module = "05"
  }
}

# --- Three VPCs ---------------------------------------------------------------

module "vpc_prod" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "archadv-${var.learner}-prod"
  cidr = "10.1.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.1.1.0/24", "10.1.2.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.common_tags
}

module "vpc_nonprod" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "archadv-${var.learner}-nonprod"
  cidr = "10.2.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.2.1.0/24", "10.2.2.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.common_tags
}

module "vpc_shared" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "archadv-${var.learner}-shared"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.common_tags
}

# --- Transit Gateway ----------------------------------------------------------

resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "archadv-${var.learner}-tgw"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  amazon_side_asn                 = 64512
  tags                            = merge(local.common_tags, { Name = "archadv-${var.learner}-tgw" })
}

resource "aws_ec2_transit_gateway_route_table" "prod" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags               = merge(local.common_tags, { Name = "prod-rt" })
}

resource "aws_ec2_transit_gateway_route_table" "nonprod" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags               = merge(local.common_tags, { Name = "nonprod-rt" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "prod" {
  subnet_ids         = module.vpc_prod.private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = module.vpc_prod.vpc_id
  tags               = merge(local.common_tags, { Name = "prod-attach" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "nonprod" {
  subnet_ids         = module.vpc_nonprod.private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = module.vpc_nonprod.vpc_id
  tags               = merge(local.common_tags, { Name = "nonprod-attach" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "shared" {
  subnet_ids         = module.vpc_shared.private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = module.vpc_shared.vpc_id
  tags               = merge(local.common_tags, { Name = "shared-attach" })
}

# prod-rt: prod + shared associated and propagated
resource "aws_ec2_transit_gateway_route_table_association" "prod_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.prod.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}
resource "aws_ec2_transit_gateway_route_table_propagation" "prod_to_prod" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.prod.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}
resource "aws_ec2_transit_gateway_route_table_propagation" "shared_to_prod" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

# nonprod-rt: nonprod + shared associated and propagated
resource "aws_ec2_transit_gateway_route_table_association" "nonprod_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.nonprod.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.nonprod.id
}
resource "aws_ec2_transit_gateway_route_table_propagation" "nonprod_to_nonprod" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.nonprod.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.nonprod.id
}
resource "aws_ec2_transit_gateway_route_table_propagation" "shared_to_nonprod" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.nonprod.id
}

# Shared-services attachment associates with prod-rt so it can reach prod;
# propagation onto both tier route tables is what lets each tier reach it.
resource "aws_ec2_transit_gateway_route_table_association" "shared_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

# --- Add TGW routes in each VPC's own route tables ---------------------------
# (For brevity, the lab uses a single private route table per VPC. Real
#  designs would use one per AZ.)

# --- S3 gateway VPC endpoint with restrictive endpoint policy ----------------

resource "aws_s3_bucket" "lab" {
  bucket = "archadv-${var.learner}-lab"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "lab" {
  bucket                  = aws_s3_bucket.lab.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "s3_endpoint" {
  # Allow access to the learner's lab bucket only.
  statement {
    sid       = "AllowLabBucket"
    effect    = "Allow"
    principals { type = "*"; identifiers = ["*"] }
    actions   = ["s3:GetObject", "s3:ListBucket", "s3:PutObject"]
    resources = [aws_s3_bucket.lab.arn, "${aws_s3_bucket.lab.arn}/*"]
  }

  # Explicit deny on every other bucket reachable through this endpoint.
  statement {
    sid       = "DenyEverythingElse"
    effect    = "Deny"
    principals { type = "*"; identifiers = ["*"] }
    actions   = ["s3:*"]
    not_resources = [aws_s3_bucket.lab.arn, "${aws_s3_bucket.lab.arn}/*"]
  }
}

resource "aws_vpc_endpoint" "s3_prod" {
  vpc_id            = module.vpc_prod.vpc_id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc_prod.private_route_table_ids
  policy            = data.aws_iam_policy_document.s3_endpoint.json
  tags              = merge(local.common_tags, { Name = "prod-s3-endpoint" })
}

# --- Outputs ------------------------------------------------------------------

output "lab_bucket" {
  value = aws_s3_bucket.lab.bucket
}

output "tgw_id" {
  value = aws_ec2_transit_gateway.tgw.id
}
