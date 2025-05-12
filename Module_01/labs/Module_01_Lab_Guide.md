
# Lab: Deploy a Well-Architected VPC

## Objective
Build a VPC with subnets, an Internet Gateway, and a public EC2 instance using Console and Terraform.

## Part A: Console Steps
1. Create a VPC (CIDR: 10.0.0.0/16)
2. Add public and private subnets
3. Create and attach an Internet Gateway
4. Create a Route Table and associate it
5. Launch an EC2 instance into the public subnet

## Part B: Terraform Steps
1. Review provided Terraform files
2. Run `terraform init` and `terraform apply`
3. Verify infrastructure in AWS Console

## Validation
- SSH to EC2
- Check public IP access
- Destroy resources with `terraform destroy`
