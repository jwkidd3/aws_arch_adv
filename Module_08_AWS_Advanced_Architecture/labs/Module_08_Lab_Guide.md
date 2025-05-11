
# Lab: Building a Highly Available and DDoS-Protected Web Architecture

## Objective
Deploy a web application behind an ALB with Auto Scaling and AWS Shield/WAF.

## Part A: AWS Console Steps
1. Create a Launch Template for EC2
2. Set up an Auto Scaling Group across 2 AZs
3. Attach an Application Load Balancer
4. Associate AWS WAF with ALB
5. Enable AWS Shield (Standard is automatic)

## Part B: Terraform Steps
1. Define launch template and ASG
2. Create ALB and target group
3. Enable WAF and associate it with ALB

## Validation
- Check EC2 health and ALB status
- Review WAF logs and test access patterns
