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
      Lab       = "05-tgw"
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

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

locals {
  azs   = slice(data.aws_availability_zones.available.names, 0, 2)
  vpcs = {
    prod    = "10.20.0.0/16"
    nonprod = "10.30.0.0/16"
    shared  = "10.10.0.0/16"
  }
}

module "vpc" {
  for_each = local.vpcs
  source   = "terraform-aws-modules/vpc/aws"
  version  = "~> 5.0"

  name = "archadv-${var.harness_owner}-lab05-${each.key}"
  cidr = each.value
  azs  = local.azs

  # Public subnets so SSM Agent can reach SSM via IGW (matches the lab's
  # post-validation patch).
  public_subnets  = [cidrsubnet(each.value, 8, 0), cidrsubnet(each.value, 8, 1)]
  private_subnets = [cidrsubnet(each.value, 8, 10), cidrsubnet(each.value, 8, 11)]

  enable_nat_gateway = false
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# --- IAM for SSM ---

resource "aws_iam_role" "ssm" {
  name = "archadv-${var.harness_owner}-lab05-ssm"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "archadv-${var.harness_owner}-lab05-ssm"
  role = aws_iam_role.ssm.name
}

# --- Per-VPC security group + EC2 in public subnet ---

resource "aws_security_group" "ec2" {
  for_each = local.vpcs
  name     = "archadv-${var.harness_owner}-lab05-${each.key}"
  vpc_id   = module.vpc[each.key].vpc_id

  ingress {
    description = "ICMP from any of the three VPCs (for cross-VPC ping tests)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ec2" {
  for_each               = local.vpcs
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = module.vpc[each.key].public_subnets[0]
  vpc_security_group_ids = [aws_security_group.ec2[each.key].id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name
  associate_public_ip_address = true

  tags = { Name = "archadv-${var.harness_owner}-lab05-${each.key}" }
}

# --- Transit Gateway ---

resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "archadv lab 5 harness"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  amazon_side_asn                 = 64512
  tags                            = { Name = "archadv-${var.harness_owner}-lab05-tgw" }
}

resource "aws_ec2_transit_gateway_route_table" "prod" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags               = { Name = "archadv-${var.harness_owner}-lab05-prod-rt" }
}

resource "aws_ec2_transit_gateway_route_table" "nonprod" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags               = { Name = "archadv-${var.harness_owner}-lab05-nonprod-rt" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "att" {
  for_each           = local.vpcs
  subnet_ids         = module.vpc[each.key].private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = module.vpc[each.key].vpc_id
  tags               = { Name = "archadv-${var.harness_owner}-lab05-${each.key}-att" }
}

# Associations: each attachment goes to one route table.
resource "aws_ec2_transit_gateway_route_table_association" "prod" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att["prod"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

resource "aws_ec2_transit_gateway_route_table_association" "nonprod" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att["nonprod"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.nonprod.id
}

resource "aws_ec2_transit_gateway_route_table_association" "shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att["shared"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

# Propagations: prod-rt ← prod + shared, nonprod-rt ← nonprod + shared.
resource "aws_ec2_transit_gateway_route_table_propagation" "prod_self" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att["prod"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "prod_shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att["shared"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "nonprod_self" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att["nonprod"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.nonprod.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "nonprod_shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att["shared"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.nonprod.id
}

# Add static routes in each VPC's route tables to send cross-VPC traffic to TGW.
resource "aws_route" "to_tgw" {
  for_each = {
    "prod-shared"     = { vpc = "prod",    rt = module.vpc["prod"].public_route_table_ids[0],    cidr = "10.10.0.0/16" }
    "prod-nonprod"    = { vpc = "prod",    rt = module.vpc["prod"].public_route_table_ids[0],    cidr = "10.30.0.0/16" }
    "nonprod-shared"  = { vpc = "nonprod", rt = module.vpc["nonprod"].public_route_table_ids[0], cidr = "10.10.0.0/16" }
    "nonprod-prod"    = { vpc = "nonprod", rt = module.vpc["nonprod"].public_route_table_ids[0], cidr = "10.20.0.0/16" }
    "shared-prod"     = { vpc = "shared",  rt = module.vpc["shared"].public_route_table_ids[0],  cidr = "10.20.0.0/16" }
    "shared-nonprod"  = { vpc = "shared",  rt = module.vpc["shared"].public_route_table_ids[0],  cidr = "10.30.0.0/16" }
  }

  route_table_id         = each.value.rt
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.att]
}

# --- S3 gateway VPC endpoint with restrictive policy ---

resource "aws_s3_bucket" "lab" {
  bucket        = "archadv-${var.harness_owner}-lab05"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lab" {
  bucket                  = aws_s3_bucket.lab.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_vpc_endpoint" "s3_prod" {
  vpc_id            = module.vpc["prod"].vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc["prod"].public_route_table_ids

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowLabBucket"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:ListBucket", "s3:PutObject"]
        Resource = [
          aws_s3_bucket.lab.arn,
          "${aws_s3_bucket.lab.arn}/*"
        ]
      },
      {
        Sid         = "DenyEverythingElse"
        Effect      = "Deny"
        Principal   = "*"
        Action      = "s3:*"
        NotResource = [
          aws_s3_bucket.lab.arn,
          "${aws_s3_bucket.lab.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_object" "test_object" {
  bucket  = aws_s3_bucket.lab.id
  key     = "lab-object.txt"
  content = "harness test object"
}
