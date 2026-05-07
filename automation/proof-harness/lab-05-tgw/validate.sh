#!/usr/bin/env bash
# Lab 5 assertions — TGW prod/non-prod isolation + S3 gateway endpoint policy.
# API-only / structural validation: confirms the architecture is built correctly.
# Real packet-flow reachability is for the instructor dry-run.

set -uo pipefail

cd "$(dirname "$0")"

if ! TF_OUT=$(terraform output -json 2>/dev/null); then
  echo "ERROR: terraform output failed — run 'terraform apply' first" >&2
  exit 2
fi

TGW_ID=$(echo "$TF_OUT" | jq -r '.tgw_id.value')
BUCKET=$(echo  "$TF_OUT" | jq -r '.lab_bucket.value')
S3_EP=$(echo   "$TF_OUT" | jq -r '.s3_endpoint_id.value')

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Lab 5 — TGW isolation + S3 gateway endpoint (structural validation)"

# 1. TGW exists and is available
TGW_STATE=$(aws ec2 describe-transit-gateways --transit-gateway-ids "$TGW_ID" \
  --query 'TransitGateways[0].State' --output text 2>/dev/null || echo "")
[[ "$TGW_STATE" == "available" ]] \
  && pass "TGW $TGW_ID is available" \
  || fail "TGW state is $TGW_STATE (expected available)"

# 2. TGW has default association/propagation disabled (manual control)
DEF_ASSOC=$(aws ec2 describe-transit-gateways --transit-gateway-ids "$TGW_ID" \
  --query 'TransitGateways[0].Options.DefaultRouteTableAssociation' --output text)
DEF_PROP=$(aws ec2 describe-transit-gateways --transit-gateway-ids "$TGW_ID" \
  --query 'TransitGateways[0].Options.DefaultRouteTablePropagation' --output text)
[[ "$DEF_ASSOC" == "disable" ]] && pass "TGW default association: disable" || fail "TGW default association: $DEF_ASSOC"
[[ "$DEF_PROP"  == "disable" ]] && pass "TGW default propagation: disable" || fail "TGW default propagation: $DEF_PROP"

# 3. Two custom TGW route tables exist (prod-rt, nonprod-rt)
RTS_JSON=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=transit-gateway-id,Values=$TGW_ID" \
            "Name=default-association-route-table,Values=false" \
  --query 'TransitGatewayRouteTables[].{Id:TransitGatewayRouteTableId,Name:Tags[?Key==`Name`]|[0].Value,State:State}' \
  --output json)
NUM_RTS=$(echo "$RTS_JSON" | jq 'length')
[[ "$NUM_RTS" == "2" ]] && pass "2 custom TGW route tables" || fail "expected 2 custom TGW RTs, got $NUM_RTS"

PROD_RT=$(echo    "$RTS_JSON" | jq -r '.[] | select(.Name | endswith("-prod-rt")) | .Id')
NONPROD_RT=$(echo "$RTS_JSON" | jq -r '.[] | select(.Name | endswith("-nonprod-rt")) | .Id')
[[ -n "$PROD_RT"    ]] && pass "prod-rt found: $PROD_RT"       || fail "prod-rt not found"
[[ -n "$NONPROD_RT" ]] && pass "nonprod-rt found: $NONPROD_RT" || fail "nonprod-rt not found"

# 4. Three TGW VPC attachments, all available
ATTS_JSON=$(aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=transit-gateway-id,Values=$TGW_ID" \
  --query 'TransitGatewayVpcAttachments[].{Id:TransitGatewayAttachmentId,Name:Tags[?Key==`Name`]|[0].Value,State:State}' \
  --output json)
NUM_ATT=$(echo "$ATTS_JSON" | jq 'length')
[[ "$NUM_ATT" == "3" ]] && pass "3 TGW VPC attachments" || fail "expected 3 TGW attachments, got $NUM_ATT"

NUM_AVAIL=$(echo "$ATTS_JSON" | jq '[.[] | select(.State == "available")] | length')
[[ "$NUM_AVAIL" == "3" ]] && pass "all 3 attachments are available" || fail "$NUM_AVAIL/3 attachments available"

PROD_ATT=$(echo    "$ATTS_JSON" | jq -r '.[] | select(.Name | endswith("-prod-att"))    | .Id')
NONPROD_ATT=$(echo "$ATTS_JSON" | jq -r '.[] | select(.Name | endswith("-nonprod-att")) | .Id')
SHARED_ATT=$(echo  "$ATTS_JSON" | jq -r '.[] | select(.Name | endswith("-shared-att"))  | .Id')

# 5. prod-rt: associated with prod-attach (and shared-attach), propagates prod + shared
PROD_ASSOCS=$(aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id "$PROD_RT" \
  --query 'Associations[].TransitGatewayAttachmentId' --output text)
echo "$PROD_ASSOCS" | tr '\t' '\n' | grep -q "$PROD_ATT" \
  && pass "prod-rt has prod-attach associated" \
  || fail "prod-rt missing prod-attach association"

PROD_PROPS=$(aws ec2 get-transit-gateway-route-table-propagations \
  --transit-gateway-route-table-id "$PROD_RT" \
  --query 'TransitGatewayRouteTablePropagations[].TransitGatewayAttachmentId' --output text)
echo "$PROD_PROPS" | tr '\t' '\n' | grep -q "$PROD_ATT" \
  && pass "prod-rt propagates prod-attach" \
  || fail "prod-rt does NOT propagate prod-attach"
echo "$PROD_PROPS" | tr '\t' '\n' | grep -q "$SHARED_ATT" \
  && pass "prod-rt propagates shared-attach" \
  || fail "prod-rt does NOT propagate shared-attach"
echo "$PROD_PROPS" | tr '\t' '\n' | grep -q "$NONPROD_ATT" \
  && fail "prod-rt SHOULD NOT propagate nonprod-attach (isolation broken)" \
  || pass "prod-rt does NOT propagate nonprod-attach (isolation correct)"

# 6. nonprod-rt: associated with nonprod-attach, propagates nonprod + shared, NOT prod
NONPROD_ASSOCS=$(aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id "$NONPROD_RT" \
  --query 'Associations[].TransitGatewayAttachmentId' --output text)
echo "$NONPROD_ASSOCS" | tr '\t' '\n' | grep -q "$NONPROD_ATT" \
  && pass "nonprod-rt has nonprod-attach associated" \
  || fail "nonprod-rt missing nonprod-attach association"

NONPROD_PROPS=$(aws ec2 get-transit-gateway-route-table-propagations \
  --transit-gateway-route-table-id "$NONPROD_RT" \
  --query 'TransitGatewayRouteTablePropagations[].TransitGatewayAttachmentId' --output text)
echo "$NONPROD_PROPS" | tr '\t' '\n' | grep -q "$NONPROD_ATT" \
  && pass "nonprod-rt propagates nonprod-attach" \
  || fail "nonprod-rt does NOT propagate nonprod-attach"
echo "$NONPROD_PROPS" | tr '\t' '\n' | grep -q "$SHARED_ATT" \
  && pass "nonprod-rt propagates shared-attach" \
  || fail "nonprod-rt does NOT propagate shared-attach"
echo "$NONPROD_PROPS" | tr '\t' '\n' | grep -q "$PROD_ATT" \
  && fail "nonprod-rt SHOULD NOT propagate prod-attach (isolation broken)" \
  || pass "nonprod-rt does NOT propagate prod-attach (isolation correct)"

# 7. S3 endpoint exists, is available, has restrictive policy
EP_STATE=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "$S3_EP" \
  --query 'VpcEndpoints[0].State' --output text 2>/dev/null || echo "")
[[ "$EP_STATE" == "available" ]] \
  && pass "S3 VPC endpoint $S3_EP is available" \
  || fail "S3 endpoint state is $EP_STATE"

POLICY=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "$S3_EP" \
  --query 'VpcEndpoints[0].PolicyDocument' --output text 2>/dev/null || echo "")
echo "$POLICY" | grep -q "DenyEverythingElse" \
  && pass "S3 endpoint policy contains DenyEverythingElse statement" \
  || fail "S3 endpoint policy missing DenyEverythingElse statement"
echo "$POLICY" | grep -q "$BUCKET" \
  && pass "S3 endpoint policy references the lab bucket" \
  || fail "S3 endpoint policy does not reference $BUCKET"

# 8. S3 endpoint is associated with prod VPC's route tables
NUM_RT_ASSOC=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "$S3_EP" \
  --query 'VpcEndpoints[0].RouteTableIds | length(@)' --output text)
[[ "$NUM_RT_ASSOC" -ge 1 ]] \
  && pass "S3 endpoint associated with $NUM_RT_ASSOC route table(s)" \
  || fail "S3 endpoint not associated with any route table"

echo
echo "==> Lab 5: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
