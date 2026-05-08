#!/usr/bin/env bash
# Lab 11 assertions — ALB + ASG + target tracking on ALBRequestCountPerTarget.

set -uo pipefail

cd "$(dirname "$0")"

source "$(cd ../../tools && pwd)/identity.sh"
OWNER=$(derive_owner_slug)

if ! TF_OUT=$(terraform output -json 2>/dev/null); then
  echo "ERROR: terraform output failed" >&2
  exit 2
fi

ALB_DNS=$(echo  "$TF_OUT" | jq -r '.alb_dns.value')
ALB_ARN=$(echo  "$TF_OUT" | jq -r '.alb_arn.value')
TG_ARN=$(echo   "$TF_OUT" | jq -r '.tg_arn.value')
ASG_NAME=$(echo "$TF_OUT" | jq -r '.asg_name.value')
POLICY=$(echo   "$TF_OUT" | jq -r '.policy_name.value')

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Lab 11 — ALB + ASG + target tracking scaling"

# 1. ALB is active
ALB_STATE=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null || echo "")
[[ "$ALB_STATE" == "active" ]] && pass "ALB is active" || fail "ALB state: $ALB_STATE"

# 2. ASG configuration: min=2, max=6, desired=2
ASG_JSON=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --output json 2>/dev/null || echo "{}")
MIN=$(echo "$ASG_JSON" | jq -r '.AutoScalingGroups[0].MinSize')
MAX=$(echo "$ASG_JSON" | jq -r '.AutoScalingGroups[0].MaxSize')
DESIRED=$(echo "$ASG_JSON" | jq -r '.AutoScalingGroups[0].DesiredCapacity')
[[ "$MIN" == "2" ]]      && pass "ASG min: 2"     || fail "ASG min: $MIN"
[[ "$MAX" == "6" ]]      && pass "ASG max: 6"     || fail "ASG max: $MAX"
[[ "$DESIRED" == "2" ]]  && pass "ASG desired: 2" || fail "ASG desired: $DESIRED"

# 3. Health check type is ELB (so unhealthy LB targets get replaced)
HC=$(echo "$ASG_JSON" | jq -r '.AutoScalingGroups[0].HealthCheckType')
[[ "$HC" == "ELB" ]] && pass "ASG health check type: ELB" || fail "ASG health check: $HC"

# 4. Wait for 2 healthy targets in TG (up to 6 min)
echo "  Waiting for ASG instances to register healthy..."
for _ in $(seq 1 36); do
  HEALTHY=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query "TargetHealthDescriptions[?TargetHealth.State=='healthy'] | length(@)" --output text 2>/dev/null || echo "0")
  [[ "$HEALTHY" -ge 2 ]] && break
  sleep 10
done
[[ "$HEALTHY" -ge 2 ]] \
  && pass "$HEALTHY/2 targets healthy" \
  || fail "only $HEALTHY/2 targets healthy after 6 min"

# 5. ALB returns 200
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${ALB_DNS}/")
[[ "$HTTP_CODE" == "200" ]] && pass "ALB returns 200" || fail "ALB returns $HTTP_CODE"

# 6. Scaling policy exists with correct metric and target value
POLICY_JSON=$(aws autoscaling describe-policies --auto-scaling-group-name "$ASG_NAME" \
  --policy-names "$POLICY" --output json 2>/dev/null || echo "{}")

POLICY_TYPE=$(echo "$POLICY_JSON" | jq -r '.ScalingPolicies[0].PolicyType')
[[ "$POLICY_TYPE" == "TargetTrackingScaling" ]] \
  && pass "policy type: TargetTrackingScaling" \
  || fail "policy type: $POLICY_TYPE"

METRIC=$(echo "$POLICY_JSON" | jq -r '.ScalingPolicies[0].TargetTrackingConfiguration.PredefinedMetricSpecification.PredefinedMetricType')
[[ "$METRIC" == "ALBRequestCountPerTarget" ]] \
  && pass "scaling metric: ALBRequestCountPerTarget" \
  || fail "scaling metric: $METRIC (expected ALBRequestCountPerTarget — the lab's whole point)"

TARGET=$(echo "$POLICY_JSON" | jq -r '.ScalingPolicies[0].TargetTrackingConfiguration.TargetValue')
[[ "$TARGET" == "10" || "$TARGET" == "10.0" ]] \
  && pass "target value: $TARGET req/min/instance" \
  || fail "target value: $TARGET (expected 10)"

# 7. CloudWatch alarms were auto-created by the policy
# Target tracking creates two alarms: AlarmHigh + AlarmLow, named with the ASG.
ALARMS=$(aws cloudwatch describe-alarms \
  --query "MetricAlarms[?contains(AlarmName, 'TargetTracking-$ASG_NAME')] | length(@)" \
  --output text 2>/dev/null || echo "0")
[[ "$ALARMS" -ge 2 ]] \
  && pass "$ALARMS CloudWatch alarms auto-created (high + low)" \
  || fail "found $ALARMS CloudWatch alarms (expected ≥2 from target tracking)"

echo
echo "==> Lab 11: $PASS passed, $FAIL failed"
echo "    NOTE: harness validates structure only. Real load-generated scale-up"
echo "          (the lab's main lesson) is for the instructor dry-run."
exit $(( FAIL > 0 ? 1 : 0 ))
