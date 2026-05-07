#!/usr/bin/env bash
# Lab 8 assertions — ALB + ASG + WAF.

set -uo pipefail

cd "$(dirname "$0")"

if ! TF_OUT=$(terraform output -json 2>/dev/null); then
  echo "ERROR: terraform output failed — run 'terraform apply' first" >&2
  exit 2
fi

ALB_DNS=$(echo  "$TF_OUT" | jq -r '.alb_dns.value')
ALB_ARN=$(echo  "$TF_OUT" | jq -r '.alb_arn.value')
TG_ARN=$(echo   "$TF_OUT" | jq -r '.tg_arn.value')
ASG_NAME=$(echo "$TF_OUT" | jq -r '.asg_name.value')
ACL_ARN=$(echo  "$TF_OUT" | jq -r '.web_acl_arn.value')
ACL_ID=$(echo   "$TF_OUT" | jq -r '.web_acl_id.value')
ACL_NAME=$(echo "$TF_OUT" | jq -r '.web_acl_name.value')

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Lab 8 — ALB + ASG + WAF"

# 1. ALB is active
ALB_STATE=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null || echo "")
[[ "$ALB_STATE" == "active" ]] && pass "ALB is active" || fail "ALB state: $ALB_STATE"

# 2. ASG has desired_capacity = 2
DESIRED=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
[[ "$DESIRED" == "2" ]] && pass "ASG desired capacity: 2" || fail "ASG desired: $DESIRED"

# 3. Wait for ASG instances to be in-service in target group (up to 6 min)
echo "  Waiting for ASG instances to register healthy in TG..."
for _ in $(seq 1 36); do
  HEALTHY=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query "TargetHealthDescriptions[?TargetHealth.State=='healthy'] | length(@)" --output text 2>/dev/null || echo "0")
  [[ "$HEALTHY" -ge 2 ]] && break
  sleep 10
done
[[ "$HEALTHY" -ge 2 ]] \
  && pass "$HEALTHY/2 targets healthy in TG" \
  || fail "only $HEALTHY/2 targets healthy after 6 min"

# 4. WAF web ACL exists and contains the expected managed rule group references
# (Use grep against raw output to avoid jq-path fragility across CLI versions.)
ACL_RAW=$(aws wafv2 get-web-acl --name "$ACL_NAME" --scope REGIONAL --id "$ACL_ID" --output json 2>/dev/null)

if [[ -n "$ACL_RAW" ]]; then
  pass "WAF web ACL exists"
  echo "$ACL_RAW" | grep -q "AWSManagedRulesCommonRuleSet"            && pass "Core rule set present"        || fail "Core rule set missing"
  echo "$ACL_RAW" | grep -q "AWSManagedRulesKnownBadInputsRuleSet"    && pass "Known bad inputs present"    || fail "Known bad inputs missing"
  echo "$ACL_RAW" | grep -q "AWSManagedRulesSQLiRuleSet"              && pass "SQLi rule set present"        || fail "SQLi rule set missing"
  echo "$ACL_RAW" | grep -q "RateBasedStatement"                      && pass "Rate-based rule present"      || fail "Rate-based rule missing"
  echo "$ACL_RAW" | grep -q '"Limit": 100\|"Limit":100'               && pass "Rate limit: 100"              || fail "Rate limit not 100"
  echo "$ACL_RAW" | grep -q '"AggregateKeyType": "IP"\|"AggregateKeyType":"IP"' && pass "Aggregation: IP"  || fail "Aggregation not IP"
else
  fail "WAF web ACL lookup returned empty"
fi

# 8. Web ACL is associated with the ALB
ASSOC=$(aws wafv2 get-web-acl-for-resource --resource-arn "$ALB_ARN" \
  --query 'WebACL.ARN' --output text 2>/dev/null || echo "")
[[ "$ASSOC" == "$ACL_ARN" ]] \
  && pass "Web ACL associated with ALB" \
  || fail "Web ACL NOT associated with ALB (got: $ASSOC)"

# 9. ALB serves traffic (test SQLi probe → expect 403)
echo "  Testing ALB + WAF (SQLi probe)..."
sleep 5  # give the ALB+WAF a moment after target health
SQLI_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${ALB_DNS}/?id=1%27%20OR%20%271%27%3D%271")
NORMAL_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${ALB_DNS}/")

[[ "$NORMAL_CODE" == "200" ]] \
  && pass "normal request returns 200" \
  || fail "normal request returns $NORMAL_CODE (expected 200)"

[[ "$SQLI_CODE" == "403" ]] \
  && pass "SQLi probe returns 403 (WAF blocking)" \
  || fail "SQLi probe returns $SQLI_CODE (expected 403 — WAF should block)"

echo
echo "==> Lab 8: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
