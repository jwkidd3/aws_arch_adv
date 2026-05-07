# Lab 9 proof harness

Builds: customer-managed KMS key with rotation enabled + S3 bucket with SSE-KMS using that CMK + an encrypted object + a Secrets Manager secret encrypted with the same CMK.

## What it asserts

- CMK exists, is `Enabled`, and has rotation on
- S3 bucket default encryption is SSE-KMS pointing at the CMK
- Bucket Key is **Disabled** (required for the kms:ViaService deny in Lab 9 Step 4)
- Encrypted S3 object has correct SSE metadata
- Decrypt-via-S3 round-trip succeeds (`aws s3 cp` reads back the plaintext)
- Secrets Manager retrieval succeeds (proves the CMK permits both S3 and Secrets Manager — i.e., **no `kms:ViaService` deny is in place**, matching the lab's "remove the deny before Part B" guidance)
- Secret has an `AWSCURRENT` version

## What it does NOT assert

- The deny statement itself works (the harness deliberately omits it, since the cross-contamination is exactly what the lab teaches). To validate the deny works, run a separate variant.
- Rotation Lambda — the SAR Lambda flow is console-driven and out of scope for the harness.

## Cost (approximate, per harness run)

- KMS CMK: $1/month prorated; effectively negligible per run
- S3 bucket + 1 object: free
- Secrets Manager secret: $0.40/month prorated; effectively negligible per run

Per run: **< $0.01**. Weekly CI: < $1/year.
