#!/usr/bin/env bash
# AMI resolver — for every "Amazon Linux 2023" or similar reference in lab guides,
# confirm the current AMI ID resolves in us-east-1. Catches AMI deprecation early.

set -euo pipefail

REGION=${AWS_REGION:-us-east-1}

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Resolving AMI references in $REGION"

# Amazon Linux 2023
AL2023=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=virtualization-type,Values=hvm" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate) | [-1].ImageId' \
  --output text --region "$REGION" 2>/dev/null || echo "")

[[ "$AL2023" == ami-* ]] \
  && pass "Amazon Linux 2023 → $AL2023" \
  || fail "Amazon Linux 2023 did not resolve to an AMI"

# AWS Storage Gateway AMI (used in Lab 4)
SG_AMI=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=aws-storage-gateway-*" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate) | [-1].ImageId' \
  --output text --region "$REGION" 2>/dev/null || echo "")

[[ "$SG_AMI" == ami-* ]] \
  && pass "AWS Storage Gateway → $SG_AMI" \
  || fail "AWS Storage Gateway AMI did not resolve"

# AWS DataSync agent AMI (used in Lab 4)
DS_AMI=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=aws-datasync-*" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate) | [-1].ImageId' \
  --output text --region "$REGION" 2>/dev/null || echo "")

[[ "$DS_AMI" == ami-* ]] \
  && pass "AWS DataSync agent → $DS_AMI" \
  || fail "AWS DataSync agent AMI did not resolve"

# Managed policies referenced across labs
for POLICY in \
  arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole \
  arn:aws:iam::aws:policy/AmazonECSTaskExecutionRolePolicy \
  arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
do
  if aws iam get-policy --policy-arn "$POLICY" >/dev/null 2>&1; then
    pass "managed policy: $POLICY"
  else
    fail "managed policy missing: $POLICY"
  fi
done

echo
echo "==> AMI/policy resolver: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
