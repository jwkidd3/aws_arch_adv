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
      Lab       = "08-alb-asg-waf"
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
  # Explicitly exclude us-east-1b — t3 family unsupported there in this account.
  filter {
    name   = "zone-name"
    values = ["us-east-1a", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# --- VPC (Lab 1 pattern) ---

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "archadv-${var.harness_owner}-lab08"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}

# --- IAM for SSM (so the ASG instances are manageable) ---

resource "aws_iam_role" "ssm" {
  name = "archadv-${var.harness_owner}-lab08-ssm"
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
  name = "archadv-${var.harness_owner}-lab08-ssm"
  role = aws_iam_role.ssm.name
}

# --- Security groups ---

resource "aws_security_group" "alb" {
  name   = "archadv-${var.harness_owner}-lab08-alb"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "asg" {
  name   = "archadv-${var.harness_owner}-lab08-asg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Launch template + ASG ---

resource "aws_launch_template" "web" {
  name_prefix   = "archadv-${var.harness_owner}-lab08-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t3.small"   # t3.micro is not supported in us-east-1b

  iam_instance_profile {
    name = aws_iam_instance_profile.ssm.name
  }

  vpc_security_group_ids = [aws_security_group.asg.id]

  user_data = base64encode(<<-EOT
    #!/bin/bash
    dnf install -y httpd
    systemctl enable --now httpd
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
    HOST=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    echo "<h1>archadv $HOST</h1>" > /var/www/html/index.html
  EOT
  )

  depends_on = [aws_iam_role_policy_attachment.ssm_core]
}

resource "aws_lb" "web" {
  name               = "archadv-${var.harness_owner}-lab08-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "web" {
  name     = "archadv-${var.harness_owner}-lab08-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path     = "/"
    matcher  = "200"
    interval = 30
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "archadv-${var.harness_owner}-lab08-asg"
  vpc_zone_identifier = module.vpc.private_subnets
  target_group_arns   = [aws_lb_target_group.web.arn]
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "archadv-${var.harness_owner}-lab08-asg"
    propagate_at_launch = true
  }

  # Tag propagation for the Course/Owner default tags
  dynamic "tag" {
    for_each = {
      Course    = "archadv"
      Owner     = var.harness_owner
      ManagedBy = "proof-harness"
      Lab       = "08-alb-asg-waf"
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# --- WAF web ACL with managed rule groups (all overridden to Block) + rate-based ---

resource "aws_wafv2_web_acl" "web" {
  name        = "archadv-${var.harness_owner}-lab08-waf"
  scope       = "REGIONAL"
  description = "archadv lab 8 web ACL"

  default_action {
    allow {}
  }

  # 1. Core rule set — override all rule actions to Block (per lab guide patch)
  rule {
    name     = "core-rules"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "core-rules"
      sampled_requests_enabled   = true
    }
  }

  # 2. Known bad inputs
  rule {
    name     = "known-bad"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "known-bad"
      sampled_requests_enabled   = true
    }
  }

  # 3. SQLi
  rule {
    name     = "sqli"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "sqli"
      sampled_requests_enabled   = true
    }
  }

  # 4. Custom rate-based
  rule {
    name     = "rate-limit"
    priority = 4
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "archadv-lab08"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.web.arn
  web_acl_arn  = aws_wafv2_web_acl.web.arn
}
