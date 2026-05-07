#!/usr/bin/env bash
# Run every implemented lab harness in sequence.
# Continues on per-lab failure so you see all failures, not just the first.

set -uo pipefail

HARNESS_ROOT="$(cd "$(dirname "$0")/../proof-harness" && pwd)"
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"

declare -a RESULTS

echo "==> Running all implemented harnesses"
echo

for D in "$HARNESS_ROOT"/lab-*; do
  LAB=$(basename "$D")
  if [[ ! -f "$D/main.tf" ]]; then
    echo "==> $LAB: STUB — skipping"
    RESULTS+=("$LAB SKIP")
    continue
  fi

  echo
  echo "================================================================"
  echo "  $LAB"
  echo "================================================================"

  if "$TOOL_DIR/run-harness.sh" "$LAB"; then
    RESULTS+=("$LAB PASS")
  else
    RESULTS+=("$LAB FAIL")
  fi
done

echo
echo "================================================================"
echo "  Summary"
echo "================================================================"
printf "%-30s %s\n" "Lab" "Status"
printf "%-30s %s\n" "---" "------"
for R in "${RESULTS[@]}"; do
  printf "%-30s %s\n" "${R% *}" "${R##* }"
done

# Exit non-zero if any failed
for R in "${RESULTS[@]}"; do
  [[ "$R" == *FAIL ]] && exit 1
done
exit 0
