
provider "aws" {
  region = "us-east-1"
}

resource "aws_organizations_organization" "org" {
  feature_set = "ALL"
}

resource "aws_organizations_account" "member" {
  name      = "DevAccount"
  email     = "dev+account@example.com"
  role_name = "OrganizationAccountAccessRole"
}

resource "aws_organizations_policy" "deny_s3" {
  name = "DenyS3"
  description = "Deny all S3 access"
  type = "SERVICE_CONTROL_POLICY"

  content = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "s3:*",
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_organizations_policy_attachment" "attach" {
  policy_id = aws_organizations_policy.deny_s3.id
  target_id = aws_organizations_account.member.id
}
