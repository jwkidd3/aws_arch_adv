#!/usr/bin/env bash
# Doc link checker — extracts every docs.aws.amazon.com / aws.amazon.com URL
# from the lab guides and confirms each resolves to a 200 (not 404).
# Catches AWS doc reorganizations.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Find all AWS doc URLs in lab guides + INSTRUCTOR.md + README.md
URLS=$(grep -rohE 'https://(docs\.aws\.amazon\.com|aws\.amazon\.com)[^[:space:]\)\>"]+' \
  "$REPO_ROOT/Module_"*/labs/*.md \
  "$REPO_ROOT/INSTRUCTOR.md" \
  "$REPO_ROOT/README.md" 2>/dev/null \
  | sed 's/[\.,;:]*$//' \
  | sort -u)

if [[ -z "$URLS" ]]; then
  echo "==> No AWS doc URLs found in lab guides — nothing to check"
  exit 0
fi

echo "==> Checking $(echo "$URLS" | wc -l | tr -d ' ') unique AWS doc URLs"

PASS=0; FAIL=0
while IFS= read -r URL; do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -L "$URL" || echo "000")
  if [[ "$CODE" == "200" ]]; then
    PASS=$((PASS+1))
  else
    echo "  FAIL ($CODE): $URL" >&2
    FAIL=$((FAIL+1))
  fi
done <<< "$URLS"

echo
echo "==> Doc link check: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
