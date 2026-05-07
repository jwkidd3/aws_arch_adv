#!/usr/bin/env bash
# Lab 4 assertions — Storage Gateway + DataSync (lightweight: AMI/IAM/S3/quota only).

set -uo pipefail

cd "$(dirname "$0")"

# Derive owner slug for resource-name lookups
source "$(cd ../../tools && pwd)/identity.sh"
OWNER=$(derive_owner_slug)

if ! TF_OUT=$(terraform output -json 2>/dev/null); then
  echo "ERROR: terraform output failed" >&2
  exit 2
fi

SGW_AMI=$(echo  "$TF_OUT" | jq -r '.storage_gateway_ami.value')
DS_AMI=$(echo   "$TF_OUT" | jq -r '.datasync_ami.value')
BUCKET=$(echo   "$TF_OUT" | jq -r '.filegw_bucket.value')
SGW_ROLE=$(echo "$TF_OUT" | jq -r '.sgw_role_arn.value')
M52X=$(echo     "$TF_OUT" | jq -r '.datasync_min_offered.value')

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Lab 4 — Storage Gateway + DataSync (lightweight)"

# 1. Storage Gateway AMI resolved
[[ "$SGW_AMI" == ami-* ]] \
  && pass "Storage Gateway AMI resolves: $SGW_AMI" \
  || fail "Storage Gateway AMI did not resolve (lab guide will fail at File Gateway launch)"

# 2. DataSync agent AMI resolved
[[ "$DS_AMI" == ami-* ]] \
  && pass "DataSync agent AMI resolves: $DS_AMI" \
  || fail "DataSync AMI did not resolve"

# 3. m5.2xlarge is offered in the region (DataSync agent minimum)
[[ "$M52X" == "true" ]] \
  && pass "m5.2xlarge is offered in this region (DataSync minimum)" \
  || fail "m5.2xlarge is NOT offered — DataSync lab will fail at agent launch"

# 4. S3 bucket created with encryption + public access blocked
SSE=$(aws s3api get-bucket-encryption --bucket "$BUCKET" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
  --output text 2>/dev/null || echo "")
[[ "$SSE" == "AES256" ]] && pass "S3 bucket has SSE-S3 enabled" || fail "S3 SSE: $SSE"

PUB=$(aws s3api get-public-access-block --bucket "$BUCKET" \
  --query 'PublicAccessBlockConfiguration.BlockPublicAcls' --output text 2>/dev/null || echo "")
[[ "$PUB" == "True" ]] && pass "S3 public access blocked" || fail "S3 public access block: $PUB"

# 5. Storage Gateway IAM role exists and trusts storagegateway.amazonaws.com
SGW_ROLE_NAME="archadv-${OWNER}-lab04-sgw"
TRUST=$(aws iam get-role --role-name "$SGW_ROLE_NAME" \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Service' --output text 2>/dev/null || echo "")
[[ "$TRUST" == "storagegateway.amazonaws.com" ]] \
  && pass "Storage Gateway role trust: storagegateway.amazonaws.com" \
  || fail "Storage Gateway role trust: $TRUST"

# 6. Inline S3 policy is attached to role
INLINE=$(aws iam list-role-policies --role-name "$SGW_ROLE_NAME" \
  --query 'PolicyNames' --output text 2>/dev/null || echo "")
echo "$INLINE" | grep -q 'lab04-sgw-s3' \
  && pass "Storage Gateway role has S3 inline policy" \
  || fail "Storage Gateway role missing S3 inline policy"

echo
echo "==> Lab 4: $PASS passed, $FAIL failed"
echo "    NOTE: this lightweight harness validates AMIs, IAM, S3, and instance-type"
echo "          availability. Actual gateway activation is covered by the instructor"
echo "          dry-run, not the harness."
exit $(( FAIL > 0 ? 1 : 0 ))
