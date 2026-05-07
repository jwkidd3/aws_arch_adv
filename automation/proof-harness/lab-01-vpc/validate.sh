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
PRIVATE_SUBNETS=()
while IFS= read -r line; do PRIVATE_SUBNETS+=("$line"); done < <(echo "$TF_OUT" | jq -r '.private_subnet_ids.value[]')
PUBLIC_SUBNETS=()
while IFS= read -r line; do PUBLIC_SUBNETS+=("$line"); done < <(echo "$TF_OUT" | jq -r '.public_subnet_ids.value[]')

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

# 6. NAT gateway is in `available` state (proves the egress path is up)
NAT_STATE=$(aws ec2 describe-route-tables --route-table-ids "$RT_ID" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId" \
  --output text 2>/dev/null | head -1)
NAT_AVAILABLE=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$NAT_STATE" \
  --query 'NatGateways[0].State' --output text 2>/dev/null || echo "")
[[ "$NAT_AVAILABLE" == "available" ]] \
  && pass "NAT gateway $NAT_STATE is available (egress path is up)" \
  || fail "NAT gateway state is $NAT_AVAILABLE (expected available)"

# 7. Workload has the SSM instance profile attached (proves IAM wiring)
PROFILE_ARN=$(aws ec2 describe-instances --instance-ids "$WORKLOAD_ID" \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text 2>/dev/null || echo "")
[[ "$PROFILE_ARN" == *":instance-profile/archadv-"*"-lab01-ssm" ]] \
  && pass "workload has SSM instance profile attached" \
  || fail "workload IAM profile is $PROFILE_ARN (expected archadv-*-lab01-ssm)"

# 8. Workload is in running state
INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids "$WORKLOAD_ID" \
  --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "")
[[ "$INSTANCE_STATE" == "running" ]] \
  && pass "workload state: running" \
  || fail "workload state is $INSTANCE_STATE (expected running)"

echo
echo "==> Lab 1: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
