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

output "web_acl_arn" {
  value = aws_wafv2_web_acl.web.arn
}

output "web_acl_id" {
  value = aws_wafv2_web_acl.web.id
}

output "web_acl_name" {
  value = aws_wafv2_web_acl.web.name
}
