#!/usr/bin/env bash
# Orchestrates one lab harness end-to-end: apply → validate → destroy.
# Cleanup script runs as a safety net even if Terraform destroy fails.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <lab-dirname>"
  echo "example: $0 lab-01-vpc"
  exit 2
fi

LAB="$1"
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$TOOL_DIR/../proof-harness" && pwd)"
LAB_DIR="$HARNESS_ROOT/$LAB"
CLEANUP_SCRIPT="$TOOL_DIR/cleanup.sh"

# Derive owner slug from AWS caller identity so multiple users sharing the
# account don't collide on resource names / cleanup tags.
source "$TOOL_DIR/identity.sh"
OWNER=$(derive_owner_slug)
[[ -z "$OWNER" || "$OWNER" == "unknown" ]] && {
  echo "ERROR: could not derive owner slug from AWS caller identity. Run 'aws configure' or set ARCHADV_OWNER." >&2
  exit 1
}
export TF_VAR_harness_owner="$OWNER"
echo "==> $LAB: owner=$OWNER"

if [[ ! -d "$LAB_DIR" ]]; then
  echo "ERROR: $LAB_DIR does not exist" >&2
  exit 2
fi

if [[ ! -f "$LAB_DIR/main.tf" ]]; then
  echo "WARN: $LAB has no main.tf — likely a stub; nothing to run" >&2
  exit 0
fi

cd "$LAB_DIR"

cleanup_on_exit() {
  echo
  echo "==> Cleanup (running terraform destroy)..."
  terraform destroy -auto-approve || true
  "$CLEANUP_SCRIPT" --owner "$OWNER" --yes || true
}
trap cleanup_on_exit EXIT

echo "==> $LAB: terraform init"
terraform init -input=false

echo "==> $LAB: terraform apply"
terraform apply -auto-approve -input=false

echo "==> $LAB: validate"
chmod +x ./validate.sh
./validate.sh
