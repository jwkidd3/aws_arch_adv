#!/usr/bin/env bash
# Lab 5 assertions — TGW prod/non-prod isolation + S3 gateway endpoint policy.

set -euo pipefail

cd "$(dirname "$0")"

if ! TF_OUT=$(terraform output -json 2>/dev/null); then
  echo "ERROR: terraform output failed — run 'terraform apply' first" >&2
  exit 2
fi

PROD_ID=$(echo    "$TF_OUT" | jq -r '.prod_ec2_id.value')
NONPROD_ID=$(echo "$TF_OUT" | jq -r '.nonprod_ec2_id.value')
SHARED_ID=$(echo  "$TF_OUT" | jq -r '.shared_ec2_id.value')
PROD_IP=$(echo    "$TF_OUT" | jq -r '.prod_ec2_private_ip.value')
NONPROD_IP=$(echo "$TF_OUT" | jq -r '.nonprod_ec2_private_ip.value')
SHARED_IP=$(echo  "$TF_OUT" | jq -r '.shared_ec2_private_ip.value')
BUCKET=$(echo     "$TF_OUT" | jq -r '.lab_bucket.value')

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Lab 5 — TGW isolation + S3 gateway endpoint"

# Wait for all 3 SSM agents to be online
echo "  Waiting for SSM agents on all 3 EC2s..."
for INST in "$PROD_ID" "$NONPROD_ID" "$SHARED_ID"; do
  for _ in $(seq 1 30); do
    STATUS=$(aws ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=$INST" \
      --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo "")
    [[ "$STATUS" == "Online" ]] && break
    sleep 10
  done
  [[ "$STATUS" == "Online" ]] || { fail "SSM agent never came online on $INST"; exit 1; }
done
pass "SSM agents online on all 3 EC2s"

# Helper: run a command on $1, return stdout (single line ok)
run_on() {
  local INST=$1
  local CMD=$2
  local RUN_ID
  RUN_ID=$(aws ssm send-command \
    --instance-ids "$INST" \
    --document-name AWS-RunShellScript \
    --parameters "commands=[\"$CMD\"]" \
    --query 'Command.CommandId' --output text)
  sleep 8
  for _ in $(seq 1 12); do
    STATE=$(aws ssm get-command-invocation \
      --command-id "$RUN_ID" --instance-id "$INST" \
      --query 'Status' --output text 2>/dev/null || echo "")
    [[ "$STATE" == "Success" || "$STATE" == "Failed" ]] && break
    sleep 5
  done
  aws ssm get-command-invocation \
    --command-id "$RUN_ID" --instance-id "$INST" \
    --query 'StandardOutputContent' --output text 2>/dev/null
}

# Helper: ping should succeed — exit 0
expect_reach() {
  local FROM=$1 TO_IP=$2 LABEL=$3
  OUT=$(run_on "$FROM" "ping -c 2 -W 2 $TO_IP > /dev/null && echo OK || echo FAIL")
  [[ "$OUT" == *OK* ]] && pass "$LABEL reachable" || fail "$LABEL NOT reachable (expected reachable)"
}

# Helper: ping should fail — that's the isolation point
expect_isolated() {
  local FROM=$1 TO_IP=$2 LABEL=$3
  OUT=$(run_on "$FROM" "ping -c 2 -W 2 $TO_IP > /dev/null && echo REACHED || echo BLOCKED")
  [[ "$OUT" == *BLOCKED* ]] && pass "$LABEL isolated as expected" || fail "$LABEL is reachable but should be ISOLATED"
}

# Connectivity matrix
expect_reach    "$SHARED_ID"  "$PROD_IP"    "shared → prod"
expect_reach    "$SHARED_ID"  "$NONPROD_IP" "shared → nonprod"
expect_reach    "$PROD_ID"    "$SHARED_IP"  "prod → shared"
expect_isolated "$PROD_ID"    "$NONPROD_IP" "prod → nonprod (TGW black-hole)"
expect_reach    "$NONPROD_ID" "$SHARED_IP"  "nonprod → shared"
expect_isolated "$NONPROD_ID" "$PROD_IP"    "nonprod → prod (TGW black-hole)"

# S3 endpoint policy assertions (run from prod-ec2)
echo "  Testing S3 endpoint policy from prod-ec2..."
OUT=$(run_on "$PROD_ID" "aws s3 ls s3://$BUCKET/ 2>&1 || echo S3_FAIL")
[[ "$OUT" == *lab-object.txt* ]] \
  && pass "prod-ec2 can list s3://$BUCKET (allowed by endpoint policy)" \
  || fail "prod-ec2 cannot list s3://$BUCKET (got: $OUT)"

OUT=$(run_on "$PROD_ID" "aws s3 ls s3://nyc-tlc/ 2>&1 || true")
[[ "$OUT" == *AccessDenied* ]] \
  && pass "prod-ec2 cannot list s3://nyc-tlc (denied by endpoint policy)" \
  || fail "prod-ec2 unexpectedly listed s3://nyc-tlc (endpoint policy not blocking; got: $OUT)"

echo
echo "==> Lab 5: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
