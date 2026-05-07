#!/usr/bin/env bash
# Lab 1 assertions — validates the lab's "Validation checklist" via AWS CLI.

set -euo pipefail

cd "$(dirname "$0")"

if ! TF_OUT=$(terraform output -json 2>/dev/null); then
  echo "ERROR: terraform output failed — run 'terraform apply' first" >&2
  exit 2
fi

VPC_ID=$(echo "$TF_OUT"        | jq -r '.vpc_id.value')
VPC_CIDR=$(echo "$TF_OUT"      | jq -r '.vpc_cidr.value')
WORKLOAD_ID=$(echo "$TF_OUT"   | jq -r '.workload_id.value')
mapfile -t PRIVATE_SUBNETS < <(echo "$TF_OUT" | jq -r '.private_subnet_ids.value[]')
mapfile -t PUBLIC_SUBNETS  < <(echo "$TF_OUT" | jq -r '.public_subnet_ids.value[]')

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Lab 1 — Well-Architected VPC"

# 1. VPC has /16 CIDR
[[ "$VPC_CIDR" == "10.0.0.0/16" ]] \
  && pass "VPC $VPC_ID has CIDR $VPC_CIDR" \
  || fail "VPC CIDR is $VPC_CIDR, expected 10.0.0.0/16"

# 2. Two public + two private subnets across two AZs
[[ ${#PUBLIC_SUBNETS[@]}  -eq 2 ]] && pass "2 public subnets present" || fail "expected 2 public subnets, got ${#PUBLIC_SUBNETS[@]}"
[[ ${#PRIVATE_SUBNETS[@]} -eq 2 ]] && pass "2 private subnets present" || fail "expected 2 private subnets, got ${#PRIVATE_SUBNETS[@]}"

# 3. Public route tables have IGW default route
for SUBNET in "${PUBLIC_SUBNETS[@]}"; do
  RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$SUBNET" \
    --query 'RouteTables[0].RouteTableId' --output text)
  GW=$(aws ec2 describe-route-tables --route-table-ids "$RT_ID" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId" \
    --output text)
  [[ "$GW" == igw-* ]] \
    && pass "public subnet $SUBNET routes 0.0.0.0/0 → $GW" \
    || fail "public subnet $SUBNET has no IGW default route (got: $GW)"
done

# 4. Private route tables have NAT default route
for SUBNET in "${PRIVATE_SUBNETS[@]}"; do
  RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$SUBNET" \
    --query 'RouteTables[0].RouteTableId' --output text)
  NAT=$(aws ec2 describe-route-tables --route-table-ids "$RT_ID" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId" \
    --output text)
  [[ "$NAT" == nat-* ]] \
    && pass "private subnet $SUBNET routes 0.0.0.0/0 → $NAT" \
    || fail "private subnet $SUBNET has no NAT default route (got: $NAT)"
done

# 5. Workload has no public IP
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$WORKLOAD_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
[[ "$PUBLIC_IP" == "None" || -z "$PUBLIC_IP" ]] \
  && pass "workload $WORKLOAD_ID has no public IP" \
  || fail "workload has public IP $PUBLIC_IP (should be private-only)"

# 6. Workload reaches internet via NAT (proves private→NAT→IGW path)
echo "  Waiting for SSM agent to come online (up to 5 min)..."
for _ in $(seq 1 30); do
  STATUS=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$WORKLOAD_ID" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo "")
  [[ "$STATUS" == "Online" ]] && break
  sleep 10
done

if [[ "$STATUS" == "Online" ]]; then
  pass "SSM agent online on workload"
  RUN_ID=$(aws ssm send-command \
    --instance-ids "$WORKLOAD_ID" \
    --document-name AWS-RunShellScript \
    --parameters 'commands=["curl -s -o /dev/null -w %{http_code} https://checkip.amazonaws.com"]' \
    --query 'Command.CommandId' --output text)
  sleep 12
  HTTP_CODE=$(aws ssm get-command-invocation \
    --command-id "$RUN_ID" --instance-id "$WORKLOAD_ID" \
    --query 'StandardOutputContent' --output text 2>/dev/null || echo "")
  [[ "$HTTP_CODE" == "200" ]] \
    && pass "workload reaches internet via NAT (HTTP 200)" \
    || fail "workload could not reach internet (HTTP code: $HTTP_CODE)"
else
  fail "SSM agent did not come online within 5 min"
fi

echo
echo "==> Lab 1: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
