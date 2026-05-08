#!/usr/bin/env bash
# Pre-class readiness probe — for every Sandbox account in the Org, check:
#   - VPC quota (recommended ≥10)
#   - vCPU running quota (recommended ≥40, headroom for Lab 4 m5.2xlarge + others)
#   - m5.2xlarge availability per AZ (Lab 4 DataSync agent)
#   - Cost Anomaly Detection enabled
#   - Resource count tagged Course=archadv (lingering from prior cohort?)
#
# Outputs a readiness table: account, vpc-quota, vcpu-quota, m52x-azs, anomaly, archadv-orphans
#
# Requires: NOT root (cross-account assumes); jq.

set -uo pipefail

# Sanity: not root
CALLER=$(aws sts get-caller-identity --query Arn --output text)
if [[ "$CALLER" == *":root" ]]; then
  echo "ERROR: you are signed in as root. AWS forbids root from assuming cross-account roles." >&2
  exit 1
fi

REGION=${AWS_REGION:-us-east-1}
ACCOUNTS_JSON=$(aws organizations list-accounts \
  --query 'Accounts[?Status==`ACTIVE` && starts_with(Name, `Sandbox`)].{Id:Id,Name:Name}' \
  --output json)
N_ACCOUNTS=$(echo "$ACCOUNTS_JSON" | jq 'length')

echo "==> Sandbox readiness probe — $N_ACCOUNTS accounts in $REGION"
printf "\n%-12s %-10s %-9s %-9s %-9s %-9s %-15s\n" \
  "Account" "Name" "vpc-q" "vcpu-q" "m52x-AZs" "anomaly" "archadv-tagged"
printf "%-12s %-10s %-9s %-9s %-9s %-9s %-15s\n" \
  "-------" "----" "-----" "------" "--------" "-------" "--------------"

probe_one() {
  local ID=$1 NAME=$2
  CREDS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::$ID:role/OrganizationAccountAccessRole" \
    --role-session-name "readiness" --duration-seconds 900 \
    --query 'Credentials' --output json 2>/dev/null)

  if [[ -z "$CREDS" || "$CREDS" == "null" ]]; then
    printf "%-12s %-10s %-9s %-9s %-9s %-9s %-15s\n" "$ID" "$NAME" "?" "?" "?" "?" "ASSUME-FAIL"
    return
  fi

  export AWS_ACCESS_KEY_ID=$(echo     "$CREDS" | jq -r .AccessKeyId)
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r .SecretAccessKey)
  export AWS_SESSION_TOKEN=$(echo     "$CREDS" | jq -r .SessionToken)

  VPC_Q=$(aws service-quotas get-service-quota \
    --service-code vpc --quota-code L-F678F1CE --region "$REGION" \
    --query 'Quota.Value' --output text 2>/dev/null | cut -d. -f1 || echo "?")

  VCPU_Q=$(aws service-quotas get-service-quota \
    --service-code ec2 --quota-code L-1216C47A --region "$REGION" \
    --query 'Quota.Value' --output text 2>/dev/null | cut -d. -f1 || echo "?")

  M52X_AZS=$(aws ec2 describe-instance-type-offerings \
    --location-type availability-zone \
    --filters "Name=instance-type,Values=m5.2xlarge" \
    --query 'InstanceTypeOfferings | length(@)' \
    --output text --region "$REGION" 2>/dev/null || echo "?")

  # Cost Anomaly Detection: any monitor at all?
  ANOMALY=$(aws ce get-anomaly-monitors --query 'AnomalyMonitors | length(@)' --output text 2>/dev/null || echo "?")

  ORPHANS=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=Course,Values=archadv" \
    --query 'ResourceTagMappingList | length(@)' \
    --output text --region "$REGION" 2>/dev/null || echo "?")

  printf "%-12s %-10s %-9s %-9s %-9s %-9s %-15s\n" "$ID" "$NAME" "$VPC_Q" "$VCPU_Q" "$M52X_AZS" "$ANOMALY" "$ORPHANS"

  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

echo "$ACCOUNTS_JSON" | jq -c '.[]' | while IFS= read -r A; do
  ID=$(echo   "$A" | jq -r .Id)
  NAME=$(echo "$A" | jq -r .Name)
  probe_one "$ID" "$NAME"
done

echo
echo "Legend:"
echo "  vpc-q     : VPCs per Region quota (recommend ≥10)"
echo "  vcpu-q    : Running On-Demand Standard vCPU quota (recommend ≥40)"
echo "  m52x-AZs  : AZs in $REGION offering m5.2xlarge (need ≥2 for Lab 4)"
echo "  anomaly   : Cost Anomaly Detection monitors (recommend ≥1)"
echo "  archadv-tagged : Resources still tagged Course=archadv (should be 0 pre-class)"
