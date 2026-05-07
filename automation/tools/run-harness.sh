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
HARNESS_ROOT="$(cd "$(dirname "$0")/../proof-harness" && pwd)"
LAB_DIR="$HARNESS_ROOT/$LAB"

if [[ ! -d "$LAB_DIR" ]]; then
  echo "ERROR: $LAB_DIR does not exist" >&2
  exit 2
fi

if [[ ! -f "$LAB_DIR/main.tf" ]]; then
  echo "WARN: $LAB has no main.tf — likely a stub; nothing to run" >&2
  exit 0
fi

cd "$LAB_DIR"

trap 'echo; echo "==> Cleanup (running terraform destroy)..."; terraform destroy -auto-approve || true; "$(dirname "$0")/cleanup.sh" --owner ci --yes || true' EXIT

echo "==> $LAB: terraform init"
terraform init -input=false

echo "==> $LAB: terraform apply"
terraform apply -auto-approve -input=false

echo "==> $LAB: validate"
chmod +x ./validate.sh
./validate.sh
