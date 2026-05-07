#!/usr/bin/env bash
# Lab 12 assertions — Budgets.

set -uo pipefail

cd "$(dirname "$0")"

if ! TF_OUT=$(terraform output -json 2>/dev/null); then
  echo "ERROR: terraform output failed" >&2
  exit 2
fi

BUDGET=$(echo "$TF_OUT" | jq -r '.budget_name.value')
ACCT=$(echo   "$TF_OUT" | jq -r '.account_id.value')

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Lab 12 — Budgets"

# 1. Budget exists with the expected limit and time unit
DESC=$(aws budgets describe-budget --account-id "$ACCT" --budget-name "$BUDGET" \
  --output json 2>/dev/null || echo "{}")

LIMIT=$(echo  "$DESC" | jq -r '.Budget.BudgetLimit.Amount')
UNIT=$(echo   "$DESC" | jq -r '.Budget.BudgetLimit.Unit')
TIMEU=$(echo  "$DESC" | jq -r '.Budget.TimeUnit')
TYPE=$(echo   "$DESC" | jq -r '.Budget.BudgetType')

[[ "$LIMIT" == "5.0" || "$LIMIT" == "5" ]] && pass "limit: \$$LIMIT" || fail "limit: $LIMIT (expected 5)"
[[ "$UNIT"  == "USD"     ]] && pass "currency: USD"          || fail "currency: $UNIT"
[[ "$TIMEU" == "MONTHLY" ]] && pass "time unit: MONTHLY"     || fail "time unit: $TIMEU"
[[ "$TYPE"  == "COST"    ]] && pass "budget type: COST"      || fail "budget type: $TYPE"

# 2. Two notifications attached: 80% ACTUAL + 100% FORECASTED
NOTIFS=$(aws budgets describe-notifications-for-budget \
  --account-id "$ACCT" --budget-name "$BUDGET" \
  --query 'Notifications' --output json 2>/dev/null || echo "[]")

NUM_NOTIF=$(echo "$NOTIFS" | jq 'length')
[[ "$NUM_NOTIF" == "2" ]] && pass "2 notifications attached" || fail "$NUM_NOTIF notifications (expected 2)"

ACTUAL_80=$(echo "$NOTIFS" | jq '[.[] | select(.NotificationType=="ACTUAL" and .Threshold==80)] | length')
[[ "$ACTUAL_80" == "1" ]] && pass "80% ACTUAL alert present" || fail "80% ACTUAL alert missing"

FORECAST_100=$(echo "$NOTIFS" | jq '[.[] | select(.NotificationType=="FORECASTED" and .Threshold==100)] | length')
[[ "$FORECAST_100" == "1" ]] && pass "100% FORECASTED alert present" || fail "100% FORECASTED alert missing"

# 3. Each notification has a subscriber
for IDX in 0 1; do
  NTYPE=$(echo "$NOTIFS" | jq -r ".[$IDX].NotificationType")
  THRESH=$(echo "$NOTIFS" | jq -r ".[$IDX].Threshold")
  SUBS=$(aws budgets describe-subscribers-for-notification \
    --account-id "$ACCT" --budget-name "$BUDGET" \
    --notification "{\"NotificationType\":\"$NTYPE\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":$THRESH,\"ThresholdType\":\"PERCENTAGE\"}" \
    --query 'Subscribers | length(@)' --output text 2>/dev/null || echo "0")
  [[ "$SUBS" -ge 1 ]] \
    && pass "$NTYPE @${THRESH}% has $SUBS subscriber(s)" \
    || fail "$NTYPE @${THRESH}% has no subscribers"
done

echo
echo "==> Lab 12: $PASS passed, $FAIL failed"
echo "    NOTE: Cost Explorer activation and cost-allocation-tag activation are"
echo "          account-level state with multi-day delays; not validated here."
exit $(( FAIL > 0 ? 1 : 0 ))
