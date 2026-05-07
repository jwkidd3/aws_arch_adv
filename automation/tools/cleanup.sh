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

set -uo pipefail
# Note: NOT using -e because we use `grep` to filter ARNs and grep returns
# non-zero when there are no matches — that's expected behavior in this script.

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

# Resource-type-aware deletion. Order matters: nuke dependents first,
# foundational things last. We do multiple passes to handle async deletes
# (NAT gateway in particular takes minutes).

aws_silent() {
  aws "$@" --region "$REGION" >/dev/null 2>&1 || true
}

# Pass 1: terminate EC2 instances (must go before subnets/SGs/VPCs)
echo "  Pass 1: EC2 instances"
echo "$ARNS" | grep ':instance/' | while IFS= read -r ARN; do
  ID=${ARN##*/}
  echo "    terminate: $ID"
  aws_silent ec2 terminate-instances --instance-ids "$ID"
done

# Pass 2: NAT gateways (slow async delete; kick off and continue)
echo "  Pass 2: NAT gateways"
echo "$ARNS" | grep ':natgateway/' | while IFS= read -r ARN; do
  ID=${ARN##*/}
  echo "    delete (async): $ID"
  aws_silent ec2 delete-nat-gateway --nat-gateway-id "$ID"
done

# Pass 3: Service-level resources that don't block anything else
echo "  Pass 3: service-level resources"
echo "$ARNS" | while IFS= read -r ARN; do
  case "$ARN" in
    *:s3:::*)
      BUCKET=${ARN##*:}
      echo "    s3 bucket: $BUCKET"
      aws s3 rm "s3://$BUCKET" --recursive --region "$REGION" >/dev/null 2>&1 || true
      aws s3 rb "s3://$BUCKET" --force --region "$REGION" >/dev/null 2>&1 || true
      ;;
    *:secretsmanager:*:secret:*)
      echo "    secrets manager: ${ARN##*:secret:}"
      aws_silent secretsmanager delete-secret --secret-id "$ARN" --force-delete-without-recovery
      ;;
    *:kms:*:key/*)
      ID=${ARN##*/}
      echo "    kms key: $ID (schedule deletion 7 days)"
      aws_silent kms schedule-key-deletion --key-id "$ID" --pending-window-in-days 7
      ;;
  esac
done

# Pass 4: TGW resources (TGW route tables and attachments first, then TGW)
echo "  Pass 4: TGW resources"
echo "$ARNS" | grep ':transit-gateway-attachment/' | while IFS= read -r ARN; do
  ID=${ARN##*/}
  echo "    tgw attachment: $ID"
  aws_silent ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id "$ID"
done
echo "$ARNS" | grep ':transit-gateway-route-table/' | while IFS= read -r ARN; do
  ID=${ARN##*/}
  echo "    tgw route table: $ID"
  aws_silent ec2 delete-transit-gateway-route-table --transit-gateway-route-table-id "$ID"
done
echo "$ARNS" | grep ':transit-gateway/' | grep -v 'attachment\|route-table' | while IFS= read -r ARN; do
  ID=${ARN##*/}
  echo "    tgw: $ID"
  aws_silent ec2 delete-transit-gateway --transit-gateway-id "$ID"
done

# Pass 5: VPC dependents — VPC endpoints, network interfaces, security groups,
# subnets, route tables, internet gateways. These can have ordering dependencies
# among themselves; we do a few iterations.
echo "  Pass 5: VPC dependents"
echo "$ARNS" | grep ':vpc-endpoint/' | while IFS= read -r ARN; do
  ID=${ARN##*/}
  echo "    vpc endpoint: $ID"
  aws_silent ec2 delete-vpc-endpoints --vpc-endpoint-ids "$ID"
done

# Wait briefly for NAT gateways to release their ENIs / route table refs
echo "  Waiting up to 5 min for NAT gateway delete to free dependents..."
NAT_IDS=$(echo "$ARNS" | grep ':natgateway/' | sed 's|.*/||' | tr '\n' ' ')
if [[ -n "$NAT_IDS" ]]; then
  for _ in $(seq 1 30); do
    PENDING=$(aws ec2 describe-nat-gateways --nat-gateway-ids $NAT_IDS \
      --query "NatGateways[?State!='deleted'].NatGatewayId" --output text 2>/dev/null || echo "")
    [[ -z "$PENDING" ]] && break
    sleep 10
  done
fi

# Release any EIPs we own (NAT gateways allocate EIPs; releasing now cleans up)
echo "  Pass 6: EIPs"
EIPS=$(aws ec2 describe-addresses \
  --filters "Name=tag:Course,Values=archadv" "Name=tag:Owner,Values=$OWNER" \
  --query 'Addresses[].AllocationId' --output text --region "$REGION" 2>/dev/null || echo "")
for EIP in $EIPS; do
  echo "    release EIP: $EIP"
  aws_silent ec2 release-address --allocation-id "$EIP"
done

# Now safe to delete subnets, SGs (non-default), RTs (non-main), IGWs, VPCs
echo "  Pass 7: subnets"
echo "$ARNS" | grep ':subnet/' | while IFS= read -r ARN; do
  ID=${ARN##*/}
  echo "    subnet: $ID"
  aws_silent ec2 delete-subnet --subnet-id "$ID"
done

echo "  Pass 8: route tables (skip main route tables)"
echo "$ARNS" | grep ':route-table/' | while IFS= read -r ARN; do
  ID=${ARN##*/}
  IS_MAIN=$(aws ec2 describe-route-tables --route-table-ids "$ID" \
    --query 'RouteTables[0].Associations[?Main==`true`] | length(@)' --output text --region "$REGION" 2>/dev/null || echo "0")
  if [[ "$IS_MAIN" == "0" ]]; then
    echo "    route table: $ID"
    aws_silent ec2 delete-route-table --route-table-id "$ID"
  else
    echo "    route table (main, skip): $ID"
  fi
done

echo "  Pass 9: security groups (skip default)"
echo "$ARNS" | grep ':security-group/' | while IFS= read -r ARN; do
  ID=${ARN##*/}
  NAME=$(aws ec2 describe-security-groups --group-ids "$ID" \
    --query 'SecurityGroups[0].GroupName' --output text --region "$REGION" 2>/dev/null || echo "")
  if [[ "$NAME" != "default" ]]; then
    echo "    security group: $ID ($NAME)"
    aws_silent ec2 delete-security-group --group-id "$ID"
  else
    echo "    security group (default, skip): $ID"
  fi
done

echo "  Pass 10: internet gateways (detach + delete)"
echo "$ARNS" | grep ':internet-gateway/' | while IFS= read -r ARN; do
  ID=${ARN##*/}
  VPC=$(aws ec2 describe-internet-gateways --internet-gateway-ids "$ID" \
    --query 'InternetGateways[0].Attachments[0].VpcId' --output text --region "$REGION" 2>/dev/null || echo "")
  if [[ -n "$VPC" && "$VPC" != "None" ]]; then
    echo "    detach: $ID from $VPC"
    aws_silent ec2 detach-internet-gateway --internet-gateway-id "$ID" --vpc-id "$VPC"
  fi
  echo "    delete: $ID"
  aws_silent ec2 delete-internet-gateway --internet-gateway-id "$ID"
done

echo "  Pass 11: VPCs"
echo "$ARNS" | grep ':vpc/' | grep -v 'vpc-endpoint\|vpc-flow' | while IFS= read -r ARN; do
  ID=${ARN##*/}
  echo "    vpc: $ID"
  aws_silent ec2 delete-vpc --vpc-id "$ID"
done

# Pass 12: IAM roles last (rarely block anything but keeping order)
echo "  Pass 12: IAM roles"
echo "$ARNS" | grep ':role/' | while IFS= read -r ARN; do
  NAME=${ARN##*/}
  echo "    iam role: $NAME"
  aws iam list-attached-role-policies --role-name "$NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null \
    | tr '\t' '\n' | while read -r P; do
      [[ -n "$P" ]] && aws iam detach-role-policy --role-name "$NAME" --policy-arn "$P" >/dev/null 2>&1 || true
    done
  aws iam list-role-policies --role-name "$NAME" --query 'PolicyNames' --output text 2>/dev/null \
    | tr '\t' '\n' | while read -r P; do
      [[ -n "$P" ]] && aws iam delete-role-policy --role-name "$NAME" --policy-name "$P" >/dev/null 2>&1 || true
    done
  aws iam list-instance-profiles-for-role --role-name "$NAME" --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null \
    | tr '\t' '\n' | while read -r IP; do
      [[ -n "$IP" ]] && aws iam remove-role-from-instance-profile --instance-profile-name "$IP" --role-name "$NAME" >/dev/null 2>&1 || true
      [[ -n "$IP" ]] && aws iam delete-instance-profile --instance-profile-name "$IP" >/dev/null 2>&1 || true
    done
  aws iam delete-role --role-name "$NAME" >/dev/null 2>&1 || true
done

echo
echo "==> Cleanup complete. Some resources may remain (e.g. NAT gateway EIPs); review the AWS console."
