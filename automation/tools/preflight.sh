#!/usr/bin/env bash
# Preflight — checks every prerequisite for running the harness.
# Run this once after install, and once per run to confirm nothing has drifted.

set -euo pipefail

PASS=0; FAIL=0; WARN=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }
warn() { echo "  WARN: $*" >&2; WARN=$((WARN+1)); }

echo "==> Preflight checks"

# --- 1. Tools installed ---

if command -v terraform >/dev/null; then
  V=$(terraform version | head -1 | awk '{print $2}' | tr -d 'v')
  pass "terraform $V"
else
  fail "terraform not installed (brew install terraform)"
fi

if command -v aws >/dev/null; then
  V=$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2)
  pass "aws-cli $V"
else
  fail "aws CLI not installed (brew install awscli)"
fi

if command -v jq >/dev/null; then
  pass "jq $(jq --version | tr -d 'jq-')"
else
  fail "jq not installed (brew install jq)"
fi

# --- 2. AWS auth ---

if AUTH=$(aws sts get-caller-identity --output json 2>/dev/null); then
  ACCT=$(echo "$AUTH" | jq -r .Account)
  ARN=$(echo "$AUTH"  | jq -r .Arn)
  pass "AWS auth: account $ACCT"
  echo "        identity: $ARN"

  # Derive the owner slug the harness will use
  source "$(dirname "$0")/identity.sh"
  OWNER=$(derive_owner_slug)
  if [[ -n "$OWNER" && "$OWNER" != "unknown" ]]; then
    pass "harness owner slug: $OWNER (used for resource names + Owner tag)"
  else
    fail "could not derive harness owner slug from caller identity"
  fi

  # Warn about root usage
  if [[ "$ARN" == *":root" ]]; then
    warn "you are signed in as the ROOT user. Tests will work, but root usage is discouraged. Prefer a power-user IAM user or IAM Identity Center session."
  fi

  # Check we're in a region
  REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-}}
  if [[ -z "$REGION" ]]; then
    PROFILE_REGION=$(aws configure get region 2>/dev/null || echo "")
    if [[ -n "$PROFILE_REGION" ]]; then
      pass "AWS region: $PROFILE_REGION (from CLI profile)"
    else
      warn "no region set (export AWS_REGION=us-east-1 or set in ~/.aws/config). Tests will default to us-east-1."
    fi
  else
    pass "AWS region: $REGION"
  fi
else
  fail "AWS auth failed — run 'aws configure' or set AWS_PROFILE"
fi

# --- 3. Sandbox sanity (basic — just confirm we can list VPCs) ---

if [[ $FAIL -eq 0 ]]; then
  if aws ec2 describe-vpcs --max-results 5 --region us-east-1 >/dev/null 2>&1; then
    pass "EC2 read access in us-east-1"
  else
    fail "cannot describe VPCs in us-east-1 — check IAM permissions"
  fi
fi

# --- 4. Test directory ---

HARNESS_ROOT="$(cd "$(dirname "$0")/../proof-harness" && pwd)"
if [[ -d "$HARNESS_ROOT" ]]; then
  pass "harness directory: $HARNESS_ROOT"
  IMPL=0
  for D in "$HARNESS_ROOT"/lab-*; do
    [[ -f "$D/main.tf" ]] && IMPL=$((IMPL+1))
  done
  echo "        $IMPL implemented harness(es) found"
else
  fail "harness directory missing: $HARNESS_ROOT"
fi

echo
echo "==> Preflight: $PASS passed, $FAIL failed, $WARN warning(s)"

if [[ $FAIL -gt 0 ]]; then
  echo "==> Setup not complete. See automation/SETUP.md."
  exit 1
fi

if [[ $WARN -gt 0 ]]; then
  echo "==> Setup OK with warnings. Tests will run."
fi

exit 0
