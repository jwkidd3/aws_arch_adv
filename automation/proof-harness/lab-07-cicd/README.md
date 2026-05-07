# Lab 7 proof harness — STUB

**Status: not yet implemented.**

## Scope when implemented

- Provision a CodeCommit repository (CodeCommit returned to GA in November 2025; verify CI Sandbox account has access)
- Provision a CodeBuild project with the right buildspec
- Provision the artifact S3 bucket
- Provision a CodePipeline with source/build/deploy stages
- Validate a triggered build succeeds end-to-end and updates the ECS service from Lab 6 (or a stand-in)

## Critical CI assertion

The single highest-value assertion is: **`pip3 install --user git-remote-codecommit && git clone codecommit::us-east-1://<repo>` works** under the CI's IAM Identity Center-equivalent role. This is the validation-pass-discovered blocker that the lab guide was patched for. If `git-remote-codecommit` ever stops working in CloudShell, students hit a wall.

## Why this is not implemented in the initial harness

The most fragile part of this lab is CodeCommit's CI behavior with rotating credentials. Build it after the foundation is proven; pair it with Lab 6's harness so the deploy stage has an ECS target.

Copy `lab-01-vpc/` as the template.
