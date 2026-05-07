#!/usr/bin/env bash
# Lab 10 assertions — S3 + Glue Crawler + Athena.

set -uo pipefail

cd "$(dirname "$0")"

if ! TF_OUT=$(terraform output -json 2>/dev/null); then
  echo "ERROR: terraform output failed — run 'terraform apply' first" >&2
  exit 2
fi

LAKE=$(echo      "$TF_OUT" | jq -r '.lake_bucket.value')
DB=$(echo        "$TF_OUT" | jq -r '.db_name.value')
CRAWLER=$(echo   "$TF_OUT" | jq -r '.crawler_name.value')
WORKGROUP=$(echo "$TF_OUT" | jq -r '.workgroup_name.value')
RESULTS=$(echo   "$TF_OUT" | jq -r '.results_bucket.value')

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Lab 10 — S3 + Glue + Athena data lake"

# 1. Lake bucket exists with public access blocked
PUB=$(aws s3api get-public-access-block --bucket "$LAKE" \
  --query 'PublicAccessBlockConfiguration.BlockPublicAcls' --output text 2>/dev/null || echo "")
[[ "$PUB" == "True" ]] && pass "$LAKE has public access blocked" || fail "$LAKE public access block: $PUB"

# 2. Seed CSVs are present under sales/year=2024/
COUNT=$(aws s3 ls "s3://$LAKE/sales/year=2024/" 2>/dev/null | grep -c '\.csv$' || echo "0")
[[ "$COUNT" -ge 2 ]] && pass "$COUNT seed CSV(s) under sales/year=2024/" || fail "expected ≥2 CSVs under sales/year=2024/, got $COUNT"

# 3. Glue database exists with hyphen-stripped name
DB_NAME=$(aws glue get-database --name "$DB" --query 'Database.Name' --output text 2>/dev/null || echo "")
[[ "$DB_NAME" == "$DB" ]] \
  && pass "Glue database $DB exists" \
  || fail "Glue database lookup failed: $DB_NAME"

# 4. Hyphen check (per the lab guide: lowercase + underscores only)
if [[ "$DB" =~ - ]]; then
  fail "Glue database name contains hyphens: $DB"
else
  pass "Glue database name is hyphen-free"
fi

# 5. Glue role has both AWSGlueServiceRole AND S3 read permissions
ROLE_NAME="archadv-ci-lab10-glue"
ATTACHED=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
  --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
echo "$ATTACHED" | grep -q 'AWSGlueServiceRole' \
  && pass "Glue role has AWSGlueServiceRole attached" \
  || fail "Glue role missing AWSGlueServiceRole"

INLINE=$(aws iam list-role-policies --role-name "$ROLE_NAME" \
  --query 'PolicyNames' --output text 2>/dev/null || echo "")
echo "$INLINE" | grep -q 'lake-s3-read' \
  && pass "Glue role has inline S3 read policy" \
  || fail "Glue role missing inline S3 read policy"

# 6. Run the Crawler
echo "  Triggering crawler $CRAWLER..."
aws glue start-crawler --name "$CRAWLER" >/dev/null 2>&1 || true

# Wait for crawler to finish (READY state means idle/finished)
for _ in $(seq 1 30); do
  STATE=$(aws glue get-crawler --name "$CRAWLER" --query 'Crawler.State' --output text 2>/dev/null || echo "")
  [[ "$STATE" == "READY" ]] && break
  sleep 10
done
[[ "$STATE" == "READY" ]] && pass "crawler reached READY state" || fail "crawler stuck in $STATE after 5 min"

# 7. Crawler last-run was successful
LAST_STATUS=$(aws glue get-crawler --name "$CRAWLER" \
  --query 'Crawler.LastCrawl.Status' --output text 2>/dev/null || echo "")
[[ "$LAST_STATUS" == "SUCCEEDED" ]] \
  && pass "crawler last run: SUCCEEDED" \
  || fail "crawler last run: $LAST_STATUS"

# 8. Sales table created in catalog with expected columns + partition
TABLE=$(aws glue get-table --database-name "$DB" --name sales \
  --query 'Table.{Cols:StorageDescriptor.Columns[].Name,Parts:PartitionKeys[].Name}' --output json 2>/dev/null || echo "{}")
COLS=$(echo "$TABLE" | jq -r '.Cols // [] | sort | join(",")')
PARTS=$(echo "$TABLE" | jq -r '.Parts // [] | join(",")')

echo "$COLS" | grep -q "order_id" && echo "$COLS" | grep -q "region" && echo "$COLS" | grep -q "revenue" \
  && pass "sales table has expected columns ($COLS)" \
  || fail "sales table missing expected columns (got: $COLS)"

[[ "$PARTS" == "year" ]] \
  && pass "sales table partition key: year" \
  || fail "sales table partition is $PARTS (expected: year)"

# 9. Submit an Athena query and validate row count
QUERY="SELECT region, SUM(revenue) AS total_revenue FROM sales WHERE year = '2024' GROUP BY region ORDER BY total_revenue DESC"
QID=$(aws athena start-query-execution \
  --query-string "$QUERY" \
  --query-execution-context "Database=$DB" \
  --work-group "$WORKGROUP" \
  --query QueryExecutionId --output text 2>/dev/null || echo "")

if [[ -z "$QID" ]]; then
  fail "Athena start-query-execution failed"
else
  for _ in $(seq 1 12); do
    QSTATE=$(aws athena get-query-execution --query-execution-id "$QID" \
      --query 'QueryExecution.Status.State' --output text 2>/dev/null || echo "")
    [[ "$QSTATE" == "SUCCEEDED" || "$QSTATE" == "FAILED" || "$QSTATE" == "CANCELLED" ]] && break
    sleep 5
  done

  if [[ "$QSTATE" == "SUCCEEDED" ]]; then
    pass "Athena query succeeded"
    NROWS=$(aws athena get-query-results --query-execution-id "$QID" \
      --query 'ResultSet.Rows | length(@)' --output text 2>/dev/null || echo "0")
    # 4 region rows + 1 header
    [[ "$NROWS" == "5" ]] \
      && pass "Athena returned 4 region rows + header (5 total)" \
      || fail "Athena returned $NROWS rows (expected 5: 4 regions + header)"
  else
    REASON=$(aws athena get-query-execution --query-execution-id "$QID" \
      --query 'QueryExecution.Status.StateChangeReason' --output text 2>/dev/null || echo "")
    fail "Athena query state: $QSTATE — $REASON"
  fi
fi

echo
echo "==> Lab 10: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
