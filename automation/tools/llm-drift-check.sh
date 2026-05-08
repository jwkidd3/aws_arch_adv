#!/usr/bin/env bash
# LLM-based lab-guide drift check.
# For each lab guide, ask Claude (via Anthropic API) to flag console paths,
# service names, AMIs, or managed-policy ARNs that may have drifted since
# the guide was written. Posts findings to stdout.
#
# Cost: ~$0.005/call with Claude Sonnet 4.6. 14 labs = ~$0.07/run.
#
# Required: ANTHROPIC_API_KEY env var.

set -uo pipefail

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ERROR: ANTHROPIC_API_KEY not set" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODEL="${ANTHROPIC_MODEL:-claude-sonnet-4-6}"

PROMPT_PREFIX='You are validating an AWS course lab guide for drift since it was written. Read the lab guide carefully and identify items that may need review:

1. AWS console click-paths — button labels, menu names, wizard flow steps that AWS has likely renamed or moved
2. Service names — AWS service or sub-feature names that have been renamed (e.g., "CodeStar Connections" → "AWS CodeConnections")
3. Deprecated services or features — anything AWS has announced sunset/retirement for
4. AMI / managed-policy / image-tag references — specific AMI names, IAM managed-policy ARNs, container image tags that may no longer exist
5. AWS doc URLs — any docs.aws.amazon.com link that has moved
6. Quota/limit values — any specific service quota the guide assumes

For each finding, output:
- LINE: <line number or section>
- ITEM: <the specific text>
- RISK: <high|medium|low>
- WHY: <one sentence>

If everything looks current, respond exactly: "NO DRIFT DETECTED".

Do NOT speculate. Only flag items you have specific reason to suspect have changed. Be conservative.

Lab guide content:
---
'

check_lab() {
  local LAB_FILE=$1
  local LAB_NAME
  LAB_NAME=$(basename "$(dirname "$LAB_FILE")")

  echo
  echo "================================================================"
  echo "  $LAB_NAME"
  echo "================================================================"

  local CONTENT
  CONTENT=$(cat "$LAB_FILE")

  # Build the request body via jq to handle escaping correctly
  local PAYLOAD
  PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg sys "$PROMPT_PREFIX" \
    --arg user "$CONTENT" \
    '{
      model: $model,
      max_tokens: 1024,
      messages: [
        { role: "user", content: ($sys + $user) }
      ]
    }')

  local RESP
  RESP=$(curl -s https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    --data "$PAYLOAD")

  if echo "$RESP" | jq -e '.error' >/dev/null 2>&1; then
    echo "  ERROR: $(echo "$RESP" | jq -r '.error.message')" >&2
    return 1
  fi

  echo "$RESP" | jq -r '.content[0].text'
}

if [[ $# -gt 0 ]]; then
  # Single lab mode
  for L in "$@"; do
    check_lab "$REPO_ROOT/Module_${L}/labs/Module_${L}_Lab_Guide.md"
  done
else
  # All labs
  for F in "$REPO_ROOT"/Module_*/labs/Module_*_Lab_Guide.md; do
    check_lab "$F"
  done
fi
