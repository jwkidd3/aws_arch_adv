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
      Lab       = "06-ecs"
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
  # Avoid us-east-1b (t3 family unsupported in this account)
  filter {
    name   = "zone-name"
    values = ["us-east-1a", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}

# --- VPC (Lab 1 pattern; required for ECS Fargate w/ private tasks) ---

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "archadv-${var.harness_owner}-lab06"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}

# --- ECR repository ---

resource "aws_ecr_repository" "hello" {
  name                 = "archadv-${var.harness_owner}-lab06-hello"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

# --- ECS cluster ---

resource "aws_ecs_cluster" "main" {
  name = "archadv-${var.harness_owner}-lab06"
}

# --- IAM: task execution role ---

resource "aws_iam_role" "task_exec" {
  name = "archadv-${var.harness_owner}-lab06-task-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_exec_managed" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- Task definition (uses a public image — skip the docker build/push) ---

resource "aws_ecs_task_definition" "hello" {
  family                   = "archadv-${var.harness_owner}-lab06-hello"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_exec.arn

  container_definitions = jsonencode([{
    name      = "web"
    image     = "public.ecr.aws/docker/library/nginx:1.27-alpine"
    essential = true
    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "web"
      }
    }
  }])

  depends_on = [aws_iam_role_policy_attachment.task_exec_managed]
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/archadv-${var.harness_owner}-lab06"
  retention_in_days = 1
}

# --- Security groups ---

resource "aws_security_group" "alb" {
  name   = "archadv-${var.harness_owner}-lab06-alb"
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

resource "aws_security_group" "tasks" {
  name   = "archadv-${var.harness_owner}-lab06-tasks"
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

# --- ALB ---

resource "aws_lb" "main" {
  name               = "archadv-${var.harness_owner}-lab06-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "tasks" {
  name        = "archadv-${var.harness_owner}-lab06-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path     = "/"
    matcher  = "200"
    interval = 30
  }
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tasks.arn
  }
}

# --- ECS service ---

resource "aws_ecs_service" "hello" {
  name            = "archadv-${var.harness_owner}-lab06-hello-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.hello.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tasks.arn
    container_name   = "web"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.main]
}
