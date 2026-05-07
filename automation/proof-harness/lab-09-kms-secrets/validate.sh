#!/usr/bin/env bash
# Lab 9 assertions — KMS CMK + S3 SSE-KMS + Secrets Manager retrieval.

set -euo pipefail

cd "$(dirname "$0")"

if ! TF_OUT=$(terraform output -json 2>/dev/null); then
  echo "ERROR: terraform output failed — run 'terraform apply' first" >&2
  exit 2
fi

KEY_ARN=$(echo  "$TF_OUT" | jq -r '.kms_key_arn.value')
KEY_ID=$(echo   "$TF_OUT" | jq -r '.kms_key_id.value')
BUCKET=$(echo   "$TF_OUT" | jq -r '.bucket.value')
OBJECT=$(echo   "$TF_OUT" | jq -r '.object_key.value')
SECRET=$(echo   "$TF_OUT" | jq -r '.secret_id.value')

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Lab 9 — KMS + Secrets Manager"

# 1. CMK exists and is enabled
STATE=$(aws kms describe-key --key-id "$KEY_ID" --query 'KeyMetadata.KeyState' --output text)
[[ "$STATE" == "Enabled" ]] \
  && pass "CMK $KEY_ID is Enabled" \
  || fail "CMK state is $STATE (expected Enabled)"

# 2. Key rotation is on
ROTATION=$(aws kms get-key-rotation-status --key-id "$KEY_ID" --query 'KeyRotationEnabled' --output text)
[[ "$ROTATION" == "True" ]] \
  && pass "CMK rotation enabled" \
  || fail "CMK rotation is $ROTATION (expected True)"

# 3. S3 default encryption is SSE-KMS with this CMK
SSE_ALG=$(aws s3api get-bucket-encryption --bucket "$BUCKET" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)
SSE_KEY=$(aws s3api get-bucket-encryption --bucket "$BUCKET" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID' --output text)
[[ "$SSE_ALG" == "aws:kms" ]] && pass "$BUCKET uses SSE-KMS" || fail "$BUCKET SSE-Alg is $SSE_ALG (expected aws:kms)"
[[ "$SSE_KEY" == "$KEY_ARN" ]] && pass "$BUCKET points at our CMK" || fail "$BUCKET KMS key is $SSE_KEY (expected $KEY_ARN)"

# 4. The encrypted object reports SSE-KMS in its head metadata
HEAD_SSE=$(aws s3api head-object --bucket "$BUCKET" --key "$OBJECT" --query 'ServerSideEncryption' --output text)
HEAD_KEY=$(aws s3api head-object --bucket "$BUCKET" --key "$OBJECT" --query 'SSEKMSKeyId' --output text)
[[ "$HEAD_SSE" == "aws:kms" ]] && pass "object SSE is aws:kms" || fail "object SSE is $HEAD_SSE"
[[ "$HEAD_KEY" == "$KEY_ARN" ]] && pass "object SSEKMSKeyId is the CMK" || fail "object SSEKMSKeyId is $HEAD_KEY"

# 5. Bucket Key is disabled (matches the lab's required state for the deny test)
BK=$(aws s3api get-bucket-encryption --bucket "$BUCKET" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].BucketKeyEnabled' --output text)
[[ "$BK" == "False" ]] \
  && pass "Bucket Key disabled (required for kms:ViaService deny test)" \
  || fail "Bucket Key is $BK (lab requires False)"

# 6. Decrypt-via-S3 round-trip works (proves IAM + key policy permits the calling principal)
DECRYPTED=$(aws s3 cp "s3://$BUCKET/$OBJECT" - 2>/dev/null || echo "DECRYPT_FAILED")
[[ "$DECRYPTED" == "harness-secret-payload" ]] \
  && pass "decrypt-via-S3 round-trip succeeds" \
  || fail "decrypt-via-S3 returned: $DECRYPTED"

# 7. Secrets Manager retrieval works (would fail if a kms:ViaService deny was on the CMK — confirms the lab's "remove the deny before Part B" guidance is correct)
SECRET_VAL=$(aws secretsmanager get-secret-value --secret-id "$SECRET" --query 'SecretString' --output text 2>/dev/null || echo "FAILED")
echo "$SECRET_VAL" | jq -e '.username' >/dev/null 2>&1 \
  && pass "Secrets Manager retrieval works (no kms:ViaService deny in place)" \
  || fail "Secrets Manager retrieval failed: $SECRET_VAL"

# 8. Secret has at least the AWSCURRENT staging label
HAS_CURRENT=$(aws secretsmanager describe-secret --secret-id "$SECRET" \
  --query 'VersionIdsToStages | values(@) | contains(@, [`AWSCURRENT`])' --output text)
[[ "$HAS_CURRENT" == "True" ]] \
  && pass "secret has AWSCURRENT version" \
  || fail "secret has no AWSCURRENT version"

echo
echo "==> Lab 9: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
