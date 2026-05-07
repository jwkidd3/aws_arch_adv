#!/usr/bin/env bash
# Bulk-request VPC-per-region quota increases across every Sandbox account in
# the org plus the management account. One request per (account × region).
#
# Usage:
#   automation/tools/quota-bulk.sh [--desired N] [--dry-run]
#
# Defaults: --desired 10
#
# Requires:
#   - You are NOT signed in as root (root cannot assume cross-account roles).
#     Sign in as a power-user IAM user in the mgmt account, OR via IAM
#     Identity Center with a role that can assume OrganizationAccountAccessRole.
#   - Each member account has the default OrganizationAccountAccessRole
#     (auto-created when accounts are made via Organizations).
#   - jq installed.

set -uo pipefail

DESIRED=10
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --desired)  DESIRED="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Sanity: not root
CALLER=$(aws sts get-caller-identity --query Arn --output text)
if [[ "$CALLER" == *":root" ]]; then
  echo "ERROR: you are signed in as root. AWS forbids root from assuming cross-account roles." >&2
  echo "       Re-auth as an IAM user or IdC role in the management account." >&2
  exit 1
fi
echo "==> Caller: $CALLER"

# Quota constants
SVC=vpc
QCODE=L-F678F1CE   # "VPCs per Region"

# Default-enabled regions (no opt-in required). Skip opt-in regions to avoid noise.
REGIONS=$(aws ec2 describe-regions --all-regions \
  --query 'Regions[?OptInStatus==`opt-in-not-required`].RegionName' --output text | tr '\t' ' ')
N_REGIONS=$(echo "$REGIONS" | wc -w | tr -d ' ')
echo "==> Targeting $N_REGIONS default-enabled regions: $REGIONS"

# All accounts in the org
ACCOUNTS_JSON=$(aws organizations list-accounts --query 'Accounts[?Status==`ACTIVE`].{Id:Id,Name:Name}' --output json)
N_ACCOUNTS=$(echo "$ACCOUNTS_JSON" | jq 'length')
MGMT_ID=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)

echo "==> $N_ACCOUNTS active accounts (including management $MGMT_ID)"
echo "==> Desired quota: $DESIRED  Dry-run: $DRY_RUN"
echo

# Result accumulators
TOTAL_REQ=0; TOTAL_OK=0; TOTAL_SKIP=0; TOTAL_FAIL=0

# Submit one request in (account, region). Returns 0 on success/skip, 1 on fail.
submit_request() {
  local PROFILE_ARGS=$1   # `--profile` if cross-account, empty if mgmt
  local REGION=$2
  local LABEL=$3
  TOTAL_REQ=$((TOTAL_REQ+1))

  if $DRY_RUN; then
    echo "    [dry-run] $LABEL"
    return 0
  fi

  # Skip if current quota already >= desired
  CURRENT=$(eval aws $PROFILE_ARGS service-quotas get-service-quota \
    --service-code $SVC --quota-code $QCODE --region "$REGION" \
    --query 'Quota.Value' --output text 2>/dev/null || echo "")
  if [[ -n "$CURRENT" && $(awk "BEGIN{print ($CURRENT >= $DESIRED)}") == "1" ]]; then
    echo "    SKIP $LABEL (already $CURRENT)"
    TOTAL_SKIP=$((TOTAL_SKIP+1))
    return 0
  fi

  # Submit the increase
  RESULT=$(eval aws $PROFILE_ARGS service-quotas request-service-quota-increase \
    --service-code $SVC --quota-code $QCODE --desired-value $DESIRED \
    --region "$REGION" --output json 2>&1)
  if echo "$RESULT" | grep -q '"Status"'; then
    STATUS=$(echo "$RESULT" | jq -r '.RequestedQuota.Status')
    echo "    OK   $LABEL → $STATUS"
    TOTAL_OK=$((TOTAL_OK+1))
    return 0
  else
    # If error contains "open request" treat as skip (existing pending)
    if echo "$RESULT" | grep -qi "open request\|DependencyAccessDenied\|already requested"; then
      echo "    SKIP $LABEL (open request exists)"
      TOTAL_SKIP=$((TOTAL_SKIP+1))
      return 0
    fi
    echo "    FAIL $LABEL: $(echo "$RESULT" | head -1)"
    TOTAL_FAIL=$((TOTAL_FAIL+1))
    return 1
  fi
}

# Process each account
echo "$ACCOUNTS_JSON" | jq -c '.[]' | while IFS= read -r ACCT; do
  ID=$(echo   "$ACCT" | jq -r .Id)
  NAME=$(echo "$ACCT" | jq -r .Name)
  echo
  echo "== $NAME ($ID)"

  if [[ "$ID" == "$MGMT_ID" ]]; then
    # Management account — use current credentials directly
    PROFILE_ARGS=""
  else
    # Member account — assume OrganizationAccountAccessRole
    CREDS=$(aws sts assume-role \
      --role-arn "arn:aws:iam::$ID:role/OrganizationAccountAccessRole" \
      --role-session-name "quota-bulk" \
      --duration-seconds 900 \
      --query 'Credentials' --output json 2>/dev/null)
    if [[ -z "$CREDS" || "$CREDS" == "null" ]]; then
      echo "    FAIL: cannot assume OrganizationAccountAccessRole in $ID — skipping"
      TOTAL_FAIL=$((TOTAL_FAIL+1))
      continue
    fi
    export AWS_ACCESS_KEY_ID=$(echo     "$CREDS" | jq -r .AccessKeyId)
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r .SecretAccessKey)
    export AWS_SESSION_TOKEN=$(echo     "$CREDS" | jq -r .SessionToken)
    PROFILE_ARGS=""   # env-var creds are picked up by aws CLI automatically
  fi

  # For each region, submit request
  for R in $REGIONS; do
    submit_request "$PROFILE_ARGS" "$R" "$NAME / $R"
  done

  # Reset env vars for next account
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
done

echo
echo "============================================================"
echo "  Summary"
echo "============================================================"
echo "  Total requests attempted: $TOTAL_REQ"
echo "  Submitted (OK):           $TOTAL_OK"
echo "  Skipped (already raised): $TOTAL_SKIP"
echo "  Failed:                   $TOTAL_FAIL"

[[ $TOTAL_FAIL -eq 0 ]] && exit 0 || exit 1
