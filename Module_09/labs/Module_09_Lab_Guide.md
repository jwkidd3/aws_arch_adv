
# Lab: Encrypting AWS Resources with KMS

## Objective
Enable encryption at rest for S3 and RDS using AWS KMS.

## Part A: Console Steps
1. Create a customer-managed KMS key
2. Enable default encryption on an S3 bucket
3. Launch an RDS instance with encryption using the KMS key
4. Store and rotate a secret with Secrets Manager

## Part B: Terraform Steps
1. Create KMS key and alias
2. Encrypt an S3 bucket using the KMS key
3. Launch encrypted RDS instance

## Validation
- Upload a file to encrypted bucket
- Connect to RDS and verify key usage in console
