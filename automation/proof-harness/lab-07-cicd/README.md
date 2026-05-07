# Lab 7 proof harness

Builds: CodeCommit repo + artifact S3 bucket + CodeBuild project (using current `aws/codebuild/amazonlinux2-x86_64-standard:5.0`) + CodePipeline with Source + Build stages.

## What it asserts

- CodeCommit repo exists (validates that this AWS account can create CodeCommit repos — relevant since CodeCommit was closed to new customers from July 2024 to Nov 2025; harness will catch a regression if AWS sunsets again)
- A file can be committed via API (`aws codecommit put-file`) — proves the repo is functional even without git CLI
- CodeBuild project exists with the current standard image
- CodePipeline has Source + Build stages
- Pipeline execution runs end-to-end and reaches `Succeeded` within 8 min
- Artifact bucket has at least one object after the run

## What it does NOT assert

- The Deploy stage (no ECS service to deploy to in this harness)
- `git-remote-codecommit` clone path — uses `aws codecommit put-file` instead, which is API-driven and doesn't require pip
- Manual approval action
- CodeStar / CodeConnections GitHub source

## Cost (approximate, per harness run)

- CodeCommit: $1/active-user/month — prorated to per-run = pennies
- CodeBuild: $0.005/build-minute on small Linux — ~$0.01 per run (2-min build)
- S3: free for this size
- CodePipeline: $1/active-pipeline/month — prorated = pennies

Per run: **~$0.02**. Weekly CI: ~$1/year.
