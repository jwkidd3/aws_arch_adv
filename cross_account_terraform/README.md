# Cross-Account IAM Access using Terraform

This example allows Account A to assume a role in Account B.

## Steps

### In Account B:
1. Deploy `iam_role_cross_account.tf` to create a role called `CrossAccountRole`.
2. This role trusts Account A (replace `ACCOUNT_A_ID`).

### In Account A:
1. Use `main.tf` and replace `ACCOUNT_B_ID` with actual Account B ID.
2. Run Terraform, and it will assume the role and return caller identity from Account B.

## Requirements:
- Terraform CLI
- Proper AWS credentials/profile configured in both accounts