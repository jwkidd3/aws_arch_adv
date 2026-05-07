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
      Lab       = "01-vpc"
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

# Resolve current Amazon Linux 2023 AMI — drift detection happens automatically
# because the AMI ID is recomputed on every plan.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "archadv-${var.harness_owner}-lab01"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}

# We use SSM (not SSH bastion) for connectivity tests in CI — same pattern
# the lab teaches as a stretch goal, equivalent reachability assertion.
resource "aws_iam_role" "ssm" {
  name = "archadv-${var.harness_owner}-lab01-ssm"
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
  name = "archadv-${var.harness_owner}-lab01-ssm"
  role = aws_iam_role.ssm.name
}

resource "aws_security_group" "workload" {
  name        = "archadv-${var.harness_owner}-lab01-workload"
  vpc_id     = module.vpc.vpc_id
  description = "Egress only — SSM uses VPC endpoints or NAT egress"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "workload" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.workload.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  tags = { Name = "archadv-${var.harness_owner}-lab01-workload" }
}
