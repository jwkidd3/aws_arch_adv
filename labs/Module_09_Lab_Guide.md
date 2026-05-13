# Lab 9 — KMS + Secrets Manager

## Objective

Create a customer-managed KMS key, encrypt an S3 object with it, then store and rotate a database password in Secrets Manager. Practice the **key policy as the source of truth** mental model.

## Time budget: 50 minutes

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. Open CloudShell.

## Part A — Customer-managed KMS key (15 min)

### 1. Create the key

- **AWS KMS → Customer managed keys → Create key**
- Type: **Symmetric**, usage: **Encrypt and decrypt**
- Alias: `archadv-<you>-key`
- Description: `archadv lab key`
- Key administrators: your IAM IdC role (search for `AWSReservedSSO_AWSAdministratorAccess_`)
- Key users: same role
- Review the **key policy** that the wizard generated. Note the structure:
  - `Enable IAM User Permissions` statement (lets your account use IAM policies to authorize access)
  - `Allow access for Key Administrators`
  - `Allow use of the key`
  - `Allow attachment of persistent resources`
- Finish.

### 2. Encrypt an S3 object with this key

- **S3 → Create bucket**: `archadv-<you>-secure`. Block public access.
- **Properties → Default encryption** → Edit → SSE-KMS → choose your CMK (`archadv-<you>-key`). **Set Bucket Key: Disable** for this lab — Bucket Key changes the KMS encryption-context shape from object-ARN to bucket-ARN, which would interact awkwardly with Step 4. (In production you typically want Bucket Key enabled for cost; this is a lab convenience.)
- Create a sample file in CloudShell and upload:

```bash
echo "secret-payload-$(date)" > secret.txt
aws s3 cp secret.txt s3://archadv-<you>-secure/
```

### 3. Validate encryption usage

```bash
aws s3api head-object --bucket archadv-<you>-secure --key secret.txt
# Look for "ServerSideEncryption": "aws:kms" and "SSEKMSKeyId": "arn:..."
```

In **CloudTrail → Event history**, find the corresponding `Decrypt` (when you re-read it) or `GenerateDataKey` (when you wrote it) call. Note: the call's `requestParameters.encryptionContext` ties the operation to the S3 object — that's the **encryption context** mechanism in action.

### 4. Tighten the key policy (5 min)

Add a statement that **only allows decrypt when the call comes via S3** (the `kms:ViaService` condition is more robust than encryption-context conditions, which break with S3 Bucket Key enabled):

```json
{
  "Sid": "DenyDecryptUnlessViaS3",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "kms:Decrypt",
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "kms:ViaService": "s3.us-east-1.amazonaws.com"
    }
  }
}
```

This denies any direct `kms:Decrypt` call that doesn't come *via* S3 — so a direct `aws kms decrypt` from CloudShell fails, but reading the encrypted S3 object still works.

**Important:** this deny will also break Part B's Secrets Manager retrieval if you keep it on the same CMK. **Remove this deny statement before starting Part B**, or use a separate CMK for Secrets Manager.

Test from CloudShell:

```bash
# Encrypt directly via KMS — works (encrypt isn't denied):
aws kms encrypt --key-id alias/archadv-<you>-key --plaintext "test" \
  --query CiphertextBlob --output text > ct.b64

# Decrypt directly via KMS — denied (kms:ViaService is not s3.*):
aws kms decrypt --ciphertext-blob fileb://<(base64 -d ct.b64)
# Expected: AccessDenied

# Decrypt via S3 — works (kms:ViaService matches):
aws s3 cp s3://archadv-<you>-secure/secret.txt -
```

Once you've observed both outcomes, **edit the key policy and remove this deny statement** before continuing to Part B.

## Part B — Secrets Manager (15 min)

### 1. Create the secret

- **Secrets Manager → Store a new secret**
- Type: **Other type of secret**
- Key/value:
  - `username` = `archadvuser`
  - `password` = (auto-generate, 20 chars, exclude special chars)
- Encryption key: your CMK from Part A
- Name: `archadv-<you>-db-pass`
- Configure rotation: **Disable** (we'll enable manually)
- Store.

### 2. Read the secret

```bash
aws secretsmanager get-secret-value --secret-id archadv-<you>-db-pass --query SecretString --output text
```

This works because (a) your IAM IdC role allows `secretsmanager:GetSecretValue`, AND (b) the KMS key policy allows `kms:Decrypt` for your role on this encryption context.

### 3. Enable rotation (5 min)

The one-click "deploy from SAR" flow inside Secrets Manager was removed years ago. You now deploy the rotation Lambda first, then attach it.

a. **Lambda → Applications → Create application → Browse serverless application repository.** Search for **SecretsManagerRotationTemplate** (publisher: AWS). Deploy with placeholder parameters (any values are fine — the endpoint won't be reachable). Wait ~3 min for the CloudFormation stack to deploy.

b. **Secrets Manager → your secret → Rotation → Edit rotation:**
   - Automatic rotation: **Enabled**, schedule: every 30 days
   - Rotation function: pick the Lambda you deployed in (a)
   - Save.

c. Click **Rotate secret immediately**. The Lambda will fail at the `setSecret` step (no MySQL to update — that's expected and fine). Observe:
   - A new secret version with `AWSPENDING` staging label appears
   - Lambda execution logs in CloudWatch show the rotation attempt and failure point

### 4. Manually rotate the secret (3 min)

- Secret → **Retrieve secret value → Edit**
- Change the password to a new value
- Save.
- Re-run `aws secretsmanager get-secret-value`. New value appears.
- Inspect: under `Versions` you can see both `AWSCURRENT` (new) and `AWSPREVIOUS` (old) — that's the staging label rotation.

## Part C — Cross-account access concept (5 min, instructor-led)

Discussion only — students will not implement.

In a real shared Org:

- A workload in `Prod` account needs the secret stored in `Security` account.
- The KMS key in `Security` must:
  - Allow the **Prod role** to call `kms:Decrypt` (resource-based key policy)
  - Have its grants visible from the Prod side (via IAM policy on the Prod role)
- The Secrets Manager **resource policy** must allow the Prod role to call `GetSecretValue`.
- This is two policies — at the secret AND at the key. Forgetting either side is the most common mistake.

## Validation checklist

- [ ] CMK created with alias and reasonable key policy
- [ ] S3 object encrypted via CMK; HEAD shows `aws:kms` SSE
- [ ] You located the `GenerateDataKey` event in CloudTrail
- [ ] Tightened key policy denies non-S3 decrypts
- [ ] Secrets Manager secret retrievable via CLI
- [ ] Secret rotation triggers a new version (even if rotation Lambda fails)

## Cleanup

1. Delete the secret (use `--force-delete-without-recovery` only if you understand the risk).
2. Delete the rotation Lambda (CloudFormation stack created by the SAR).
3. Schedule the KMS key for deletion (7-day waiting period — that's by design).
4. Empty and delete the S3 bucket.

## Stretch goals

- Add a **CloudHSM cluster** to the discussion. When would you use HSM-backed keys vs KMS? (Answer: regulated workloads requiring FIPS 140-2 Level 3, or "single-tenant" key custody.)
- Configure **automatic key rotation** on the CMK (annual, AWS-managed). Note: AWS rotates the *key material* but the key ARN stays the same — applications never change.
- Set up **Secrets Manager replica secrets** in another region for DR. Walk through what fails over if the primary region is down.
