
# Lab: Deploying Containers in AWS

## Objective
Deploy a containerized application using Amazon ECS on Fargate.

## Part A: Console Steps
1. Create an ECS Cluster
2. Define a Task Definition
3. Deploy a Service using Fargate
4. Expose the application using an ALB

## Part B: Terraform Steps
1. Use aws_ecs_cluster and aws_ecs_task_definition
2. Launch a Fargate Service with ALB
3. Use aws_lb, aws_lb_target_group, and aws_lb_listener

## Validation
- Access application through ALB DNS
- Confirm task is running and responding
