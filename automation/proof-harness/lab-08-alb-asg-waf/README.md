# Lab 8 proof harness

Builds: VPC + ALB + ASG (2 instances) + WAF web ACL with three managed rule groups + custom rate-based rule, all wired together.

## What it asserts

- ALB is `active`
- ASG desired capacity is 2
- 2/2 targets become `healthy` in the target group within 6 min
- WAF web ACL exists with 4 rules
- Rules 1–3 are managed rule groups (CRS, Known bad inputs, SQLi)
- Rule 4 is a rate-based rule with limit 100, aggregation IP
- Web ACL is associated with the ALB
- Normal `GET /` returns 200
- SQLi probe `?id=1' OR '1'='1` returns **403** (proves WAF managed rules are blocking — this is what the Lab 8 patch was about)

## What it does NOT assert

- Rate-based rule firing — would require sending 100 requests in a tight loop, ~3-4 min wall clock, and the WAF rolling counter is best-effort. Skip in CI.
- CloudWatch `BlockedRequests` metric — present-but-empty until WAF actually blocks; covered by the SQLi 403 assertion.

## Cost (approximate, per harness run)

- ALB: $0.0225/hr base
- 2 EC2 t3.micro: ~$0.02/hr
- NAT Gateway: $0.045/hr
- WAF web ACL: $5/month + $1/rule/month + $0.60/M requests — prorated to per-run = pennies

Per run (~12 min wall clock): **~$0.05**. Weekly CI: ~$2.60/year.
