# Lab 6 proof harness

Builds: VPC + ECR repo + ECS Fargate cluster + task definition (uses public nginx image — skips the docker build/push) + ALB + ECS service with 2 tasks.

## What it asserts

- ECR repository exists with valid repository URI
- ECS cluster is `ACTIVE`
- ECS service stabilizes with 2 running tasks
- 2 targets healthy in the ALB target group
- ALB returns HTTP 200 on `/` (proves the full flow: ALB → TG → ENI → Fargate task → nginx)
- Task definition uses `awsvpc` network mode (Fargate requirement)
- Tasks have NO public IP (proves NAT egress + private subnet pattern)

## What it does NOT assert

- Docker build & push from CloudShell — uses public ECR image instead. To validate Docker availability in CloudShell, see the May 2026 doc-validation memo.
- Rolling update behavior — not part of the smoke test.
- The student-facing console clicks for service create.

## Cost (approximate, per harness run)

- NAT Gateway: $0.045/hr
- ALB: $0.0225/hr base + LCU
- 2 Fargate tasks (0.25 vCPU, 0.5 GB): ~$0.012/hr each
- ECR: free for this size

Per run (~12 min wall clock): **~$0.05**. Weekly CI: ~$2.60/year.
