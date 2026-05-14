#!/usr/bin/env bash
# nuke-sandboxes.sh — post-class destruction of all Sandbox accounts.
#
# Run from the MANAGEMENT account (CloudShell or local with mgmt creds).
# Discovers all accounts in the Sandbox OU, assumes the
# OrganizationAccountAccessRole into each, and runs aws-nuke.
#
# Defaults to DRY-RUN. Pass --confirm to actually destroy.
#
# Usage:
#   ./nuke-sandboxes.sh                       # dry-run preview, all sandboxes
#   ./nuke-sandboxes.sh --confirm             # actually destroy, all sandboxes
#   ./nuke-sandboxes.sh --only Sandbox1       # operate on a single account
#   ./nuke-sandboxes.sh --confirm --only Sandbox1
#
# Tested against ekristen/aws-nuke v3. For legacy rebuy-de/aws-nuke v2,
# change `blocklist:` to `account-blocklist:` and change the invocation
# from `aws-nuke run --config <f>` to `aws-nuke -c <f>`.

set -euo pipefail

MGMT_ACCOUNT="001613358280"
SANDBOX_OU_NAME="Sandbox"
APPROVED_REGIONS=("us-east-1" "us-east-2")
ROLE_NAME="OrganizationAccountAccessRole"
SESSION_NAME="archadv-cleanup"
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGDIR="$WORKDIR/logs"
mkdir -p "$LOGDIR"

CONFIRM=false
ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) CONFIRM=true; shift ;;
    --only)    ONLY="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- Preflight ------------------------------------------------------------
CURRENT=$(aws sts get-caller-identity --query Account --output text)
if [[ "$CURRENT" != "$MGMT_ACCOUNT" ]]; then
  echo "ERROR: must run from mgmt account $MGMT_ACCOUNT. Current: $CURRENT" >&2
  exit 1
fi
command -v aws-nuke >/dev/null || { echo "aws-nuke not on PATH" >&2; exit 1; }

# --- Discover Sandbox accounts -------------------------------------------
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
SANDBOX_OU_ID=$(aws organizations list-organizational-units-for-parent \
  --parent-id "$ROOT_ID" \
  --query "OrganizationalUnits[?Name=='$SANDBOX_OU_NAME'].Id" --output text)
[[ -z "$SANDBOX_OU_ID" ]] && { echo "ERROR: OU '$SANDBOX_OU_NAME' not found" >&2; exit 1; }

mapfile -t ROWS < <(aws organizations list-accounts-for-parent \
  --parent-id "$SANDBOX_OU_ID" \
  --query 'Accounts[?Status==`ACTIVE`].[Id,Name]' --output text)
[[ ${#ROWS[@]} -eq 0 ]] && { echo "ERROR: no ACTIVE Sandbox accounts" >&2; exit 1; }

if [[ -n "$ONLY" ]]; then
  mapfile -t ROWS < <(printf '%s\n' "${ROWS[@]}" | awk -F'\t' -v n="$ONLY" '$2==n')
  [[ ${#ROWS[@]} -eq 0 ]] && { echo "ERROR: account '$ONLY' not in Sandbox OU" >&2; exit 1; }
fi

echo "Targeting ${#ROWS[@]} account(s):"
printf '  %s\n' "${ROWS[@]}"
echo ""
$CONFIRM && echo "*** DESTRUCTIVE MODE — 10s to abort ***" && sleep 10 || echo "DRY-RUN MODE (pass --confirm to destroy)"
echo ""

# --- Per-account nuke -----------------------------------------------------
nuke_account() {
  local acct_id="$1" acct_name="$2"
  local cfg="$WORKDIR/nuke-$acct_id.yaml"
  local log="$LOGDIR/$acct_name-$acct_id-$(date +%Y%m%d-%H%M%S).log"

  # Per-account config
  {
    echo "regions:"
    for r in "${APPROVED_REGIONS[@]}"; do echo "  - $r"; done
    echo "  - global"
    echo ""
    echo "blocklist:"
    echo "  - $MGMT_ACCOUNT"
    echo ""
    echo "accounts:"
    echo "  \"$acct_id\":"
    echo "    filters:"
    echo "      IAMRole:"
    echo "        - type: glob"
    echo "          value: \"AWSReservedSSO_*\""
    echo "        - \"$ROLE_NAME\""
    echo "        - type: glob"
    echo "          value: \"aws-service-role/*\""
    echo "      IAMRolePolicy:"
    echo "        - type: glob"
    echo "          value: \"AWSReservedSSO_*\""
    echo "      IAMRolePolicyAttachment:"
    echo "        - type: glob"
    echo "          value: \"AWSReservedSSO_*\""
    echo "        - type: contains"
    echo "          value: \"$ROLE_NAME\""
    echo "      IAMSAMLProvider:"
    echo "        - type: glob"
    echo "          value: \"AWSSSO_*\""
  } > "$cfg"

  # Assume into the Sandbox
  local creds
  creds=$(aws sts assume-role \
    --role-arn "arn:aws:iam::$acct_id:role/$ROLE_NAME" \
    --role-session-name "$SESSION_NAME" \
    --duration-seconds 3600 \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text 2>/dev/null) || {
      echo "  [$acct_name $acct_id] ASSUME-ROLE FAILED — skipping" | tee -a "$log"
      return
    }

  read -r AK SK ST <<<"$creds"

  echo "  [$acct_name $acct_id] starting — log: $log"
  if $CONFIRM; then
    AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" AWS_SESSION_TOKEN="$ST" \
      aws-nuke run --config "$cfg" --no-dry-run --no-prompt --force --force-sleep 3 \
      >"$log" 2>&1 || echo "  [$acct_name] aws-nuke exited non-zero (check $log)"
  else
    AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" AWS_SESSION_TOKEN="$ST" \
      aws-nuke run --config "$cfg" \
      >"$log" 2>&1 || echo "  [$acct_name] aws-nuke exited non-zero (check $log)"
  fi
  echo "  [$acct_name $acct_id] done"
}

# Sequential by default. To parallelize: change the loop to background
# the call and `wait` at the end. Sequential is safer for first run.
for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r id name <<<"$row"
  nuke_account "$id" "$name"
done

echo ""
echo "All accounts processed. Logs in $LOGDIR"
$CONFIRM || echo "This was a DRY RUN — re-run with --confirm to actually destroy."
