#!/usr/bin/env bash
# Bulk-create AWS Cost Anomaly Detection monitors across every Sandbox account.
# Each account gets a service-level monitor that flags anomalous spend.
# Pairs with auto-cleanup: anomaly fires when a Sandbox has stuck resources.
#
# Requires: NOT root.

set -uo pipefail

CALLER=$(aws sts get-caller-identity --query Arn --output text)
if [[ "$CALLER" == *":root" ]]; then
  echo "ERROR: not from root user — cross-account assumes blocked." >&2
  exit 1
fi

ALERT_EMAIL="${ALERT_EMAIL:-noreply@example.com}"

echo "==> Bulk Cost Anomaly Detection setup — alert email: $ALERT_EMAIL"

ACCOUNTS=$(aws organizations list-accounts \
  --query 'Accounts[?Status==`ACTIVE` && starts_with(Name, `Sandbox`)].{Id:Id,Name:Name}' \
  --output json)

OK=0; SKIP=0; FAIL=0

echo "$ACCOUNTS" | jq -c '.[]' | while IFS= read -r A; do
  ID=$(echo "$A" | jq -r .Id)
  NAME=$(echo "$A" | jq -r .Name)
  echo
  echo "== $NAME ($ID)"

  CREDS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::$ID:role/OrganizationAccountAccessRole" \
    --role-session-name "anomaly-bulk" --duration-seconds 900 \
    --query 'Credentials' --output json 2>/dev/null)
  if [[ -z "$CREDS" || "$CREDS" == "null" ]]; then
    echo "  FAIL: cannot assume role"
    FAIL=$((FAIL+1)); continue
  fi
  export AWS_ACCESS_KEY_ID=$(echo     "$CREDS" | jq -r .AccessKeyId)
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r .SecretAccessKey)
  export AWS_SESSION_TOKEN=$(echo     "$CREDS" | jq -r .SessionToken)

  EXISTING=$(aws ce get-anomaly-monitors \
    --query "AnomalyMonitors[?MonitorName=='archadv-${NAME}-services'] | length(@)" \
    --output text 2>/dev/null || echo "0")

  if [[ "$EXISTING" -ge 1 ]]; then
    echo "  SKIP: monitor already exists"
    SKIP=$((SKIP+1))
  else
    MONITOR_ARN=$(aws ce create-anomaly-monitor \
      --anomaly-monitor "{\"MonitorName\":\"archadv-${NAME}-services\",\"MonitorType\":\"DIMENSIONAL\",\"MonitorDimension\":\"SERVICE\"}" \
      --query 'MonitorArn' --output text 2>/dev/null || echo "")
    if [[ -z "$MONITOR_ARN" || "$MONITOR_ARN" == "None" ]]; then
      echo "  FAIL: create-anomaly-monitor returned empty"
      FAIL=$((FAIL+1))
    else
      aws ce create-anomaly-subscription --anomaly-subscription "{
        \"SubscriptionName\":\"archadv-${NAME}-alerts\",
        \"MonitorArnList\":[\"$MONITOR_ARN\"],
        \"Subscribers\":[{\"Type\":\"EMAIL\",\"Address\":\"$ALERT_EMAIL\"}],
        \"Threshold\":10,
        \"Frequency\":\"DAILY\"
      }" >/dev/null 2>&1 || true
      echo "  OK: monitor $MONITOR_ARN"
      OK=$((OK+1))
    fi
  fi

  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
done

echo
echo "==> Summary: $OK created, $SKIP skipped, $FAIL failed"
