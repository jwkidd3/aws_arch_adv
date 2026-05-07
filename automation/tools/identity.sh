#!/usr/bin/env bash
# Derives a sanitized owner slug from the current AWS caller identity.
# Used to namespace proof-harness resources so multiple users in a shared
# account don't collide.
#
# Resolution order:
#   1. $ARCHADV_OWNER env var (manual override)
#   2. aws sts get-caller-identity:
#        :root          → "root"
#        :user/<name>   → "<name>"
#        :assumed-role/<role>/<session-name> → "<session-name>"
#   3. fallback: "unknown"
#
# Output is sanitized to: lowercase, alphanumeric + hyphens, max 20 chars.

derive_owner_slug() {
  if [[ -n "${ARCHADV_OWNER:-}" ]]; then
    printf '%s' "$ARCHADV_OWNER" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed -E 's/-+/-/g; s/^-+//; s/-+$//' | cut -c1-20
    return
  fi

  local ARN RAW
  ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) || { printf 'unknown'; return; }

  case "$ARN" in
    *:root)
      RAW="root"
      ;;
    *:user/*)
      RAW="${ARN##*:user/}"
      ;;
    *:assumed-role/*)
      # Last path component is the role-session-name
      RAW="${ARN##*/}"
      ;;
    *)
      RAW="unknown"
      ;;
  esac

  # Sanitize: lowercase, hyphen-separated, max 20 chars
  printf '%s' "$RAW" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' '-' \
    | sed -E 's/-+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-20 \
    | sed -E 's/-+$//'
}

# If invoked directly (not sourced), print the slug
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  derive_owner_slug
  echo
fi
