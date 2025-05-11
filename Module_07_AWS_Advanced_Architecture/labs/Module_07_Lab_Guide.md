
# Lab: CI/CD Pipeline with GitHub Actions and Terraform

## Objective
Use GitHub Actions to deploy infrastructure into AWS using Terraform.

## Part A: GitHub Actions Steps
1. Create a GitHub repository
2. Create .github/workflows/deploy.yml
3. Configure GitHub OIDC provider for AWS
4. Create IAM role for GitHub Actions with AssumeRole policy

## Part B: Terraform Project Setup
1. Create Terraform files for an S3 bucket
2. Store remote state in another bucket
3. Use GitHub Actions to run plan and apply

## Validation
- Confirm resource created via GitHub run
- Check CloudTrail for access logs
- Review state in remote backend
