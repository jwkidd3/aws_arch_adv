#!/usr/bin/env bash
# clean-keep-lab1-vpc.sh — between-days cleanup.
#
# Clears out residual Day 1/Day 2 resources in every Sandbox account
# but PRESERVES the Lab 1 VPC and its wizard-created components, plus
# the SSM role used by Labs 11 / 14-slice-B, plus the IdC sign-in
# roles and OrganizationAccountAccessRole.
#
# Run from the MANAGEMENT account (CloudShell or local with mgmt creds).
#
# Defaults to DRY-RUN. Pass --confirm to actually destroy.
#
# Usage:
#   ./clean-keep-lab1-vpc.sh                       # dry-run, all sandboxes
#   ./clean-keep-lab1-vpc.sh --confirm             # actually destroy, all
#   ./clean-keep-lab1-vpc.sh --only Sandbox1       # dry-run, single account
#   ./clean-keep-lab1-vpc.sh --confirm --only Sandbox1
#
# Tested against ekristen/aws-nuke v3.
#
# What this preserves (NOT deleted):
#   - VPC whose Name tag matches archadv-*-vpc (Lab 1's VPC)
#   - That VPC's wizard-created subnets, route tables, IGW, NAT, EIP
#     (all match the Name pattern archadv-*-vpc-*)
#   - IAM role archadv-*-ssm-role (Lab 11 SSM instance profile)
#   - IAM Identity Center roles (AWSReservedSSO_*)
#   - OrganizationAccountAccessRole (so we can re-run cleanup)
#   - AWS service-linked roles
#
# What this DELETES (intended targets):
#   - ALL EC2 instances, ALBs, NLBs, target groups, ASGs, LTs
#   - ALL non-Lab-1 VPCs (Lab 5's prod/nonprod/shared VPCs and their components)
#   - Lab 5 TGW, attachments, route tables, VPC endpoints, RAM shares
#   - ALL ECS clusters, services, task defs, ECR repos
#   - CodePipeline / CodeBuild / CodeDeploy artifacts + S3 artifact buckets
#   - WAF web ACLs and rule groups
#   - Lambda functions, IAM roles other than the safelist above
#   - DataSync agents, locations, tasks (Lab 4 residue)
#   - DMS replication instances and endpoints (if any leaked from Lab 13)
#   - All archadv-* S3 buckets (Lab 1 doesn't use S3)

set -euo pipefail

MGMT_ACCOUNT="001613358280"
SANDBOX_OU_NAME="Sandbox"
APPROVED_REGIONS=("us-east-1" "us-east-2")
ROLE_NAME="OrganizationAccountAccessRole"
SESSION_NAME="archadv-clean-between-days"
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

echo "Targeting ${#ROWS[@]} account(s) — preserving Lab 1 VPC + SSM role + IdC:"
printf '  %s\n' "${ROWS[@]}"
echo ""
if $CONFIRM; then
  echo "*** DESTRUCTIVE MODE — 10s to abort ***"; sleep 10
else
  echo "DRY-RUN MODE (pass --confirm to destroy)"
fi
echo ""

# --- Per-account clean ----------------------------------------------------
clean_account() {
  local acct_id="$1" acct_name="$2"
  local cfg="$WORKDIR/clean-$acct_id.yaml"
  local log="$LOGDIR/$acct_name-$acct_id-keep-vpc-$(date +%Y%m%d-%H%M%S).log"

  cat > "$cfg" <<EOF
regions:
$(for r in "${APPROVED_REGIONS[@]}"; do echo "  - $r"; done)
  - global

blocklist:
  - $MGMT_ACCOUNT

accounts:
  "$acct_id":
    filters:
      # ---- Preserve Lab 1 VPC and wizard-created components ----
      EC2VPC:
        - type: glob
          property: tag:Name
          value: "archadv-*-vpc"
      EC2Subnet:
        - type: glob
          property: tag:Name
          value: "archadv-*-vpc-subnet-*"
      EC2RouteTable:
        - type: glob
          property: tag:Name
          value: "archadv-*-vpc-rtb-*"
      EC2InternetGateway:
        - type: glob
          property: tag:Name
          value: "archadv-*-vpc-igw"
      EC2InternetGatewayAttachment:
        - type: glob
          property: tag:Name
          value: "archadv-*-vpc-igw"
      EC2NATGateway:
        - type: glob
          property: tag:Name
          value: "archadv-*-vpc-nat-*"
      EC2Address:
        - type: glob
          property: tag:Name
          value: "archadv-*-vpc-eip-*"
      EC2DHCPOption:
        # default DHCP option set; safe to keep all
        - type: glob
          property: ID
          value: "dopt-*"

      # ---- Preserve identity / role plumbing ----
      IAMRole:
        - type: glob
          value: "AWSReservedSSO_*"
        - "$ROLE_NAME"
        - type: glob
          value: "aws-service-role/*"
        - type: glob
          value: "archadv-*-ssm-role"
      IAMInstanceProfile:
        - type: glob
          value: "archadv-*-ssm-role"
      IAMInstanceProfileRole:
        - type: glob
          property: role:RoleName
          value: "archadv-*-ssm-role"
      IAMRolePolicy:
        - type: glob
          value: "AWSReservedSSO_*"
      IAMRolePolicyAttachment:
        - type: glob
          value: "AWSReservedSSO_*"
        - type: contains
          value: "$ROLE_NAME"
        - type: contains
          value: "archadv-*-ssm-role"
        - type: contains
          value: "AmazonSSMManagedInstanceCore"
      IAMSAMLProvider:
        - type: glob
          value: "AWSSSO_*"
EOF

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

for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r id name <<<"$row"
  clean_account "$id" "$name"
done

echo ""
echo "All accounts processed. Logs in $LOGDIR"
$CONFIRM || echo "This was a DRY RUN — re-run with --confirm to actually destroy."
echo ""
echo "After running with --confirm, verify by visiting one Sandbox:"
echo "  - VPC console should show only archadv-<student>-vpc (1 VPC, not 4)"
echo "  - EC2 console should show 0 instances"
echo "  - ECS, CodePipeline, WAF consoles should be empty"
echo "  - IAM should still show archadv-<student>-ssm-role + AWSReservedSSO_*"
