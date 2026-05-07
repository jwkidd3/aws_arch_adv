# Lab 8 proof harness — STUB

**Status: not yet implemented.**

## Scope when implemented

- Provision a fresh VPC (or reuse Lab 1's pattern inline)
- Provision an EC2 launch template with the user-data nginx
- Provision an Auto Scaling Group across 2 AZs with target-tracking on CPU
- Provision an ALB and target group
- Provision a WAF Web ACL with the three managed rule groups + rate-based custom rule
- Associate the Web ACL with the ALB

## Validation

- ALB returns 200 from each ASG instance (round-robin)
- SQLi-shape probe `?id=1' OR '1'='1` → 403 (asserts WAF Block override is configured correctly)
- Rate-based rule fires after 100 req in 5 min → 403s
- CloudWatch `AWS/WAFV2` metric `BlockedRequests` ticks up

## Why this is not implemented in the initial harness

The Lab 8 patches (WAF rule action override, rate-based rule wording) are subtle and would be valuable to lock in CI. Implement after the foundation is proven.

Copy `lab-01-vpc/` and `lab-05-tgw/` as templates. The WAF resource definitions in Terraform are well-documented in the AWS provider.
