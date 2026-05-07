output "alb_dns" {
  value = aws_lb.main.dns_name
}

output "alb_arn" {
  value = aws_lb.main.arn
}

output "tg_arn" {
  value = aws_lb_target_group.tasks.arn
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_name" {
  value = aws_ecs_service.hello.name
}

output "ecr_repo" {
  value = aws_ecr_repository.hello.name
}

output "ecr_uri" {
  value = aws_ecr_repository.hello.repository_url
}
