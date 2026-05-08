#!/usr/bin/env bash
# Org-wide auto-cleanup. Loops every Sandbox account and runs cleanup against
# any resources tagged Course=archadv (regardless of Owner — this is the
# post-class nuker, not the per-user cleanup).
#
# Run on a daily schedule (cron, launchd, or GitHub Actions) to catch stuck
# resources from the prior cohort.
#
# Requires: NOT root.

set -uo pipefail

CALLER=$(aws sts get-caller-identity --query Arn --output text)
if [[ "$CALLER" == *":root" ]]; then
  echo "ERROR: not from root user — cross-account assumes blocked." >&2
  exit 1
fi

DRY_RUN=false
MAX_AGE_HOURS=${MAX_AGE_HOURS:-24}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --max-age-hours) MAX_AGE_HOURS="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

REGION=${AWS_REGION:-us-east-1}
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
ACCOUNTS=$(aws organizations list-accounts \
  --query 'Accounts[?Status==`ACTIVE` && starts_with(Name, `Sandbox`)].{Id:Id,Name:Name}' \
  --output json)

echo "==> Org-wide auto-cleanup — region $REGION, max age ${MAX_AGE_HOURS}h, dry-run $DRY_RUN"
TOTAL_ACCOUNTS=$(echo "$ACCOUNTS" | jq 'length')
TOTAL_RESOURCES=0
TOTAL_DELETED=0

echo "$ACCOUNTS" | jq -c '.[]' | while IFS= read -r A; do
  ID=$(echo "$A" | jq -r .Id)
  NAME=$(echo "$A" | jq -r .Name)
  echo
  echo "== $NAME ($ID)"

  CREDS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::$ID:role/OrganizationAccountAccessRole" \
    --role-session-name "org-cleanup" --duration-seconds 900 \
    --query 'Credentials' --output json 2>/dev/null)
  if [[ -z "$CREDS" || "$CREDS" == "null" ]]; then
    echo "  FAIL: cannot assume role"
    continue
  fi

  export AWS_ACCESS_KEY_ID=$(echo     "$CREDS" | jq -r .AccessKeyId)
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r .SecretAccessKey)
  export AWS_SESSION_TOKEN=$(echo     "$CREDS" | jq -r .SessionToken)

  # Find every Owner tag value present in this account under Course=archadv
  OWNERS=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=Course,Values=archadv" \
    --region "$REGION" \
    --query 'ResourceTagMappingList[].Tags[?Key==`Owner`].Value | [].@' \
    --output text 2>/dev/null | tr '\t' '\n' | sort -u)

  if [[ -z "$OWNERS" ]]; then
    echo "  No archadv-tagged resources."
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    continue
  fi

  # For each owner slug found, run cleanup.sh
  for OWNER in $OWNERS; do
    [[ -z "$OWNER" ]] && continue
    echo "  Cleaning Owner=$OWNER..."
    if $DRY_RUN; then
      "$TOOL_DIR/cleanup.sh" --owner "$OWNER" --dry-run
    else
      "$TOOL_DIR/cleanup.sh" --owner "$OWNER" --yes
    fi
  done

  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
done

echo
echo "==> Org-wide cleanup complete"
