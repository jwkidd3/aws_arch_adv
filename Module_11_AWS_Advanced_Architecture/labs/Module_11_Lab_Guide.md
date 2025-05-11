
# Lab: Building a Scalable Application Using AWS Services

## Objective
Deploy a multi-tier, auto-scaling application with caching and event processing.

## Part A: Console Steps
1. Create a Load Balancer and Auto Scaling Group
2. Create an SQS Queue and SNS Topic
3. Deploy an API Gateway with Lambda backend
4. Add CloudFront in front of application

## Part B: Terraform Steps
1. Deploy EC2 with ASG + ALB
2. Add Lambda + API Gateway
3. Attach CloudFront and configure caching

## Validation
- Test load generation across tiers
- Monitor performance in CloudWatch
- Check event propagation in SQS
