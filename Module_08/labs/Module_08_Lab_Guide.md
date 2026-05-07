# Lab 8 — ALB + ASG + WAF

## Objective

Build a horizontally-scaled web tier (ALB + ASG) and protect it with **AWS WAF** using AWS-managed rule groups + a custom rate-based rule. Then validate by triggering a SQLi-shape request and a brute-force loop.

## Time budget: 50 minutes

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. Reuse the VPC from Lab 1, or use the default VPC.

## Steps

### 1. Launch template (5 min)

- **EC2 → Launch templates → Create launch template**
- Name: `archadv-<you>-lt`
- AMI: Amazon Linux 2023
- Instance type: `t3.micro`
- Key pair: don't include — we'll use SSM
- Security group: create new — allow `80/tcp` from the soon-to-be-created **ALB's security group** (you can attach this in step 3 after the ALB SG exists)
- IAM instance profile: a role with `AmazonSSMManagedInstanceCore`
- User data:

```bash
#!/bin/bash
dnf install -y httpd
systemctl enable --now httpd
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
HOST=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
echo "<h1>archadv $HOST</h1>" > /var/www/html/index.html
```

- Create.

### 2. Application Load Balancer (5 min)

- **EC2 → Load Balancers → Create → Application**
- Name: `archadv-<you>-alb`
- Scheme: internet-facing
- VPC: yours; mappings: 2 public subnets across 2 AZs
- Security group: new — `80/tcp` from `0.0.0.0/0`
- Listener: HTTP:80
- Target group: create a new target group for **instances**, port 80, health check `/`
- Create. Wait until `Active` (~2 min).

Now go back to your launch template's security group and allow `80/tcp` from the ALB SG.

### 3. Auto Scaling Group (5 min)

- **EC2 → Auto Scaling Groups → Create**
- Name: `archadv-<you>-asg`
- Launch template: yours, latest version
- VPC: yours; subnets: 2 **private** subnets across 2 AZs
- Attach to the load balancer's target group from step 2
- Health check type: **ELB**
- Group size: desired 2, min 2, max 4
- Scaling policy: target tracking, average CPU 50%
- Create. Wait ~3 min until 2 instances are `InService` in the target group.

### 4. Validate the baseline

```bash
ALB=$(aws elbv2 describe-load-balancers --names archadv-<you>-alb --query 'LoadBalancers[0].DNSName' --output text)
for i in 1 2 3 4 5; do curl -s http://$ALB; done
```

You should see two different instance IDs alternating — that's the ALB round-robin.

### 5. AWS WAF web ACL (10 min)

- **AWS WAF & Shield → Web ACLs → Create web ACL**
- Region: us-east-1
- Name: `archadv-<you>-waf`
- Resource type: regional resources
- Add the existing ALB as an associated resource
- Add managed rule groups (in this order — WAF evaluates rules top-down):
  1. **AWS managed rules → Core rule set** (AWSManagedRulesCommonRuleSet)
  2. **AWS managed rules → Known bad inputs** (AWSManagedRulesKnownBadInputsRuleSet)
  3. **AWS managed rules → SQL database** (AWSManagedRulesSQLiRuleSet)
- For each rule group, expand it and set **"Override all rule actions to" → Block**. (Several CRS rules default to `Count`, not `Block`. Without this override, the SQLi probe in step 6 may return 200.)
- Default action: **Allow**
- Create.

### 6. Trigger a managed-rule block (3 min)

```bash
curl "http://$ALB/?id=1' OR '1'='1"
# Expected: 403 Forbidden — blocked by SQLi rule group
```

In **AWS WAF → Web ACLs → archadv-<you>-waf → Sampled requests** within ~2 min: the request appears with `BLOCK` and the matched rule.

### 7. Custom rate-based rule (10 min)

Add a rule to the same web ACL:

- Add rule → **Rate-based rule**
- Name: `archadv-rate-limit`
- Rate limit: `100`; **Evaluation window:** 5 min; **Request aggregation:** Source IP
- Action: **Block**
- Save.

Trigger it from CloudShell:

```bash
for i in $(seq 1 200); do curl -s -o /dev/null -w "%{http_code}\n" http://$ALB/; done | sort | uniq -c
```

After ~100 requests in quick succession, you should see many `403`s — the rate-based rule kicked in.

In **CloudWatch → Metrics → AWS/WAFV2** find the `BlockedRequests` metric for your web ACL and confirm the spike.

## Validation checklist

- [ ] ALB serves traffic from 2 ASG instances (round-robin)
- [ ] SQLi-shape request returns 403
- [ ] WAF Sampled requests shows the BLOCK with matched rule
- [ ] Rate-based rule blocks traffic above 100/5min
- [ ] CloudWatch `BlockedRequests` ticks up

## Cleanup

1. WAF web ACL → disassociate ALB → delete web ACL.
2. ASG → set desired/min to 0, then delete.
3. Launch template → delete.
4. ALB → delete; target group → delete.
5. Security groups → delete.

## Stretch goals

- Add an **AWS Shield Advanced** subscription discussion (do NOT enable it — $3,000/mo). Look at the Shield protections summary page.
- Add a CloudFront distribution in front of the ALB and re-test. WAF should now be associated with the CloudFront distribution (global) instead of the ALB (regional).
- Set the WAF rules to `Count` instead of `Block` for one day in production. Why? (Answer: you observe what *would* be blocked before going hot. Most teams skip this and regret it.)
