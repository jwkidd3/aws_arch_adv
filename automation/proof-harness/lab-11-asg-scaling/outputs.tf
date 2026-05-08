output "alb_dns" {
  value = aws_lb.web.dns_name
}

output "alb_arn" {
  value = aws_lb.web.arn
}

output "tg_arn" {
  value = aws_lb_target_group.web.arn
}

output "asg_name" {
  value = aws_autoscaling_group.web.name
}

output "policy_arn" {
  value = aws_autoscaling_policy.request_count.arn
}

output "policy_name" {
  value = aws_autoscaling_policy.request_count.name
}
