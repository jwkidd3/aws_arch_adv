
# Lab: Deploying Scalable Data Stores on AWS

## Objective
Provision Amazon Aurora and DynamoDB with auto-scaling and secure access.

## Part A: Console Steps
1. Create an Aurora DB Cluster with Multi-AZ
2. Configure an IAM role for DB access
3. Create a DynamoDB table with on-demand capacity
4. Enable encryption and point-in-time recovery

## Part B: Terraform Steps
1. Create an Aurora cluster and DB instance
2. Create DynamoDB table with TTL and scaling policies

## Validation
- Connect to Aurora via client
- Insert/read data from DynamoDB
- Verify CloudWatch metrics and logs
