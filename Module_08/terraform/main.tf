
provider "aws" {
  region = "us-east-1"
}

resource "aws_launch_template" "web" {
  name_prefix   = "web-lt"
  image_id      = "ami-0c02fb55956c7d316"
  instance_type = "t3.micro"

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "web-instance"
    }
  }
}

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]
  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "web-instance"
    propagate_at_launch = true
  }
}

resource "aws_lb" "app_lb" {
  name               = "app-loadbalancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-xxxxxxxx"]
  subnets            = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]

  enable_deletion_protection = false
}

resource "aws_lb_target_group" "tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-xxxxxxxx"
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}
