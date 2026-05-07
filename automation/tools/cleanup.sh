#!/usr/bin/env bash
# Tag-keyed cleanup script — nukes resources tagged Course=archadv + Owner=<owner>.
# Safety net for: failed terraform destroy, orphaned resources after class, CI test runs.
#
# Usage:
#   cleanup.sh --owner <owner> [--yes] [--dry-run]
#
# By default prints what it WOULD delete and prompts for confirmation.
# --yes skips the prompt (use in CI).
# --dry-run prints only; deletes nothing.

set -euo pipefail

OWNER=""
YES=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)   OWNER="$2"; shift 2 ;;
    --yes)     YES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$OWNER" ]] && { echo "ERROR: --owner required" >&2; exit 2; }

REGION=${AWS_REGION:-us-east-1}

echo "==> archadv cleanup — Region: $REGION, Owner: $OWNER, Dry-run: $DRY_RUN"
echo

# Use Resource Groups Tagging API to find every taggable resource matching both tags.
RAW=$(aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=Course,Values=archadv" "Key=Owner,Values=$OWNER" \
  --region "$REGION" \
  --output json)

ARNS=$(echo "$RAW" | jq -r '.ResourceTagMappingList[].ResourceARN')

if [[ -z "$ARNS" ]]; then
  echo "  No tagged resources found — nothing to do."
  exit 0
fi

echo "  Found resources:"
echo "$ARNS" | sed 's/^/    /'
echo

if $DRY_RUN; then
  echo "  --dry-run set; exiting without deletion."
  exit 0
fi

if ! $YES; then
  read -p "Delete these resources? (yes/N) " confirm
  [[ "$confirm" != "yes" ]] && { echo "Aborted."; exit 0; }
fi

# Resource-type-aware deletion. Order matters (dependencies first).
delete_arn() {
  local ARN=$1
  case "$ARN" in
    *:ec2:*:instance/*)
      ID=${ARN##*/}
      echo "  ec2 instance: $ID"
      aws ec2 terminate-instances --instance-ids "$ID" --region "$REGION" >/dev/null || true
      ;;
    *:ec2:*:vpc/*)
      ID=${ARN##*/}
      echo "  vpc: $ID  (delete VPC manually after dependents are gone — TF should have done this)"
      aws ec2 delete-vpc --vpc-id "$ID" --region "$REGION" >/dev/null || true
      ;;
    *:ec2:*:transit-gateway/*)
      ID=${ARN##*/}
      echo "  transit gateway: $ID"
      aws ec2 delete-transit-gateway --transit-gateway-id "$ID" --region "$REGION" >/dev/null || true
      ;;
    *:s3:::*)
      BUCKET=${ARN##*:}
      echo "  s3 bucket: $BUCKET"
      aws s3 rm "s3://$BUCKET" --recursive --region "$REGION" >/dev/null 2>&1 || true
      aws s3 rb "s3://$BUCKET" --force --region "$REGION" >/dev/null 2>&1 || true
      ;;
    *:secretsmanager:*:secret:*)
      ID=${ARN}
      echo "  secrets manager: $ID"
      aws secretsmanager delete-secret --secret-id "$ID" --force-delete-without-recovery --region "$REGION" >/dev/null || true
      ;;
    *:kms:*:key/*)
      ID=${ARN##*/}
      echo "  kms key: $ID (schedule deletion 7 days)"
      aws kms schedule-key-deletion --key-id "$ID" --pending-window-in-days 7 --region "$REGION" >/dev/null || true
      ;;
    *:iam::*:role/*)
      NAME=${ARN##*/}
      echo "  iam role: $NAME"
      # Detach managed policies first, then delete
      aws iam list-attached-role-policies --role-name "$NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null \
        | tr '\t' '\n' \
        | while read -r P; do [[ -n "$P" ]] && aws iam detach-role-policy --role-name "$NAME" --policy-arn "$P" >/dev/null 2>&1 || true; done
      aws iam list-role-policies --role-name "$NAME" --query 'PolicyNames' --output text 2>/dev/null \
        | tr '\t' '\n' \
        | while read -r P; do [[ -n "$P" ]] && aws iam delete-role-policy --role-name "$NAME" --policy-name "$P" >/dev/null 2>&1 || true; done
      aws iam list-instance-profiles-for-role --role-name "$NAME" --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null \
        | tr '\t' '\n' \
        | while read -r IP; do [[ -n "$IP" ]] && aws iam remove-role-from-instance-profile --instance-profile-name "$IP" --role-name "$NAME" >/dev/null 2>&1 || true; done
      aws iam delete-role --role-name "$NAME" >/dev/null 2>&1 || true
      ;;
    *)
      echo "  unhandled type: $ARN  (manual cleanup may be required)"
      ;;
  esac
}

while IFS= read -r ARN; do
  delete_arn "$ARN"
done <<< "$ARNS"

echo
echo "==> Cleanup complete. Some resources may remain (e.g. NAT gateway EIPs); review the AWS console."
