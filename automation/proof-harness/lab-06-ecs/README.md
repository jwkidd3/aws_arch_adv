# Lab 6 proof harness — STUB

**Status: not yet implemented.**

## Scope when implemented

- Provision an ECR repository
- Build the `nginx:alpine` image and push to ECR — needs Docker available in CI runner (`docker://` or `kaniko`)
- Provision an ECS Fargate cluster, task definition, and service
- Provision an ALB with IP-target target group, listener, security groups
- Validate `curl <ALB-DNS>` returns the expected payload
- Validate rolling update path: push v2 image, update task def, watch tasks drain

## Notes for implementer

- GitHub Actions runners have Docker; this is straightforward
- Reuse the Lab 1 VPC pattern (build a fresh VPC inline rather than depending on Lab 1's harness)
- The lab guide explicitly requires Lab 1's VPC (private subnets + NAT) — don't use the default VPC

## Why this is not implemented in the initial harness

ECR + ECS + ALB on a fresh VPC takes ~10-12 min apply + ~3 min destroy and runs ~$0.10/hr while up. Weekly CI for this lab is ~$5/year. Worth implementing once the foundation is proven.

Copy `lab-01-vpc/` and `lab-05-tgw/` as templates.
