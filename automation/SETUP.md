# Setup — proof harness tests

Step-by-step setup. After this, you can run any test with one command and Claude can execute them on request.

## Test layout

Each lab's test is self-contained in its own folder under `automation/proof-harness/`:

```
automation/proof-harness/
├── lab-01-vpc/                   # full implementation
│   ├── main.tf                   # builds the lab end-state
│   ├── outputs.tf                # exposes values for assertions
│   ├── validate.sh               # asserts the lab's validation checklist
│   └── README.md                 # what this test does + cost
├── lab-05-tgw/                   # full implementation
│   ├── main.tf
│   ├── outputs.tf
│   ├── validate.sh
│   └── README.md
├── lab-09-kms-secrets/           # full implementation
│   ├── main.tf
│   ├── outputs.tf
│   ├── validate.sh
│   └── README.md
└── lab-{04,06,07,08,10,12}-*/    # stubs — README only, awaiting implementation
```

You can `cd` into any test folder and run `terraform apply && ./validate.sh && terraform destroy` directly. The `automation/tools/run-harness.sh` orchestrator does this for you with a cleanup safety-net.

## 1. Prerequisites (one-time, local)

You need:

- **Terraform >= 1.5** — `brew install terraform` on macOS
- **AWS CLI v2** — `brew install awscli`
- **jq** — `brew install jq`

Run the preflight to verify:

```bash
automation/tools/preflight.sh
```

Expected output: every check passes.

## 2. AWS account for tests

Tests create real AWS resources (VPCs, EC2s, TGW, KMS keys, etc.) and tear them down at the end. They cost real money — a few cents per run, ~$5–10/year on a weekly cron.

**Use a dedicated Sandbox account.** Do NOT run these against a production account.

You have two options:

### Option A — Run locally as a privileged IAM user / SSO session

Configure your AWS CLI profile so `aws sts get-caller-identity` returns the Sandbox account. Either:

- `aws configure` with an access key, OR
- `aws configure sso` with IAM Identity Center (recommended), OR
- export `AWS_PROFILE=sandbox` (or whatever you named the profile)

Permissions needed: `PowerUserAccess` is fine. The harness creates and destroys VPC, EC2, TGW, IAM roles, KMS, S3, and Secrets Manager resources.

### Option B — Run via GitHub Actions OIDC (for CI)

See `.github/workflows/validate-labs.yml`. One-time setup:

1. Create IAM role `archadv-ci-harness` in the Sandbox account
2. Trust policy: GitHub OIDC for this repo (`token.actions.githubusercontent.com:sub` matches `repo:OWNER/REPO:*`)
3. Attach `PowerUserAccess`
4. Add GitHub secret `AWS_HARNESS_ROLE_ARN` with the role ARN
5. Trigger the workflow manually first (`workflow_dispatch`) to confirm before relying on the weekly cron

## 3. First-time test run (verify locally)

Run the smallest test (Lab 1, ~$0.05) end-to-end:

```bash
automation/tools/run-harness.sh lab-01-vpc
```

What this does:

1. `terraform init` in the lab folder
2. `terraform apply -auto-approve` (~3 min)
3. `validate.sh` runs assertions via AWS CLI / SSM (~2 min)
4. `terraform destroy -auto-approve` (~2 min)
5. `cleanup.sh --owner ci --yes` runs as safety net (catches orphans)

Expected output ends with:

```
==> Lab 1: 8 passed, 0 failed
```

## 4. Running other tests

```bash
# Lab 5 (TGW + S3 endpoint, ~25 min, ~$0.10)
automation/tools/run-harness.sh lab-05-tgw

# Lab 9 (KMS + Secrets Manager, ~5 min, ~$0.01)
automation/tools/run-harness.sh lab-09-kms-secrets

# All implemented labs in sequence
automation/tools/run-all.sh
```

## 5. Manual cleanup (if a run fails badly)

If `terraform destroy` fails and `cleanup.sh` doesn't catch everything (rare), run it explicitly:

```bash
# Dry-run first
automation/tools/cleanup.sh --owner ci --dry-run

# Actually delete
automation/tools/cleanup.sh --owner ci --yes
```

The script targets only resources tagged `Course=archadv` AND `Owner=ci`. Nothing else is touched.

## 6. Owner slug — multi-user shared-account safety

The harness derives an **owner slug** from your AWS caller identity and uses it in resource names + the `Owner` tag. This lets multiple users in a shared account run the harness concurrently without collisions.

| Caller identity | Slug |
|---|---|
| `arn:aws:iam::ACCT:root` | `root` |
| `arn:aws:iam::ACCT:user/alice` | `alice` |
| `arn:aws:sts::ACCT:assumed-role/AWSReservedSSO_X/alice@example.com` | `alice-example-com` (sanitized) |

To see the slug your session resolves to:

```bash
automation/tools/identity.sh
```

To override (e.g., to use a fixed slug for CI):

```bash
export ARCHADV_OWNER=ci-runner
automation/tools/run-harness.sh lab-01-vpc
```

Resources are named `archadv-<slug>-labNN-*` and tagged `Owner=<slug>` + `Course=archadv`. The cleanup script targets only resources matching the **current** caller's slug — so cleaning up after your run doesn't touch other users' resources.

## 7. Asking Claude to run a test

After setup, tell Claude:

> "Run lab-01"
> "Run lab-05 and report what fails"
> "Run all implemented harnesses"

Claude will invoke `automation/tools/run-harness.sh <lab>` (or `run-all.sh`) and report the output. Cleanup runs automatically (scoped to your owner slug).

If you want a test run that DOESN'T destroy at the end (so you can inspect resources):

```bash
cd automation/proof-harness/lab-01-vpc
terraform init
terraform apply -auto-approve
./validate.sh
# inspect what you want, then:
terraform destroy -auto-approve
```

## 7. Adding a stub-only lab

The 6 stubs (`lab-04`, `lab-06`, `lab-07`, `lab-08`, `lab-10`, `lab-12`) have READMEs explaining scope but no `main.tf`. To implement one:

1. `cp -r automation/proof-harness/lab-01-vpc automation/proof-harness/lab-NN-name`
2. Replace `main.tf` to build the lab's end-state
3. Replace `outputs.tf` with the values your assertions need
4. Replace `validate.sh` with the assertions
5. Add `lab-NN-name` to the matrix in `.github/workflows/validate-labs.yml`
6. Run `automation/tools/run-harness.sh lab-NN-name` to confirm

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `terraform: command not found` | Terraform not installed | `brew install terraform` |
| `Unable to locate credentials` | AWS CLI not configured | `aws configure` or set `AWS_PROFILE` |
| `AccessDenied` on TGW or VPC | Sandbox SCP restricting region or service | Check Sandbox OU's SCPs in the management account |
| `InsufficientInstanceCapacity` | AZ-specific capacity issue in us-east-1a | Re-run; harness picks first 2 AZs and capacity shifts |
| `DependencyViolation` on destroy | TGW route tables still have associations | Re-run `automation/tools/cleanup.sh --owner ci --yes` |
| Cleanup script reports "unhandled type" | Resource type not in the cleanup-script switch | Manual delete in console; consider patching `cleanup.sh` |

## Cost summary

| Lab | Per run | Weekly CI / year |
|---|---|---|
| Lab 1 | ~$0.05 | ~$2.60 |
| Lab 5 | ~$0.10 | ~$5.20 |
| Lab 9 | ~$0.01 | ~$0.50 |
| **Total** (3 implemented) | **~$0.16** | **~$8.30** |

If you implement the 6 stubs, weekly CI cost rises to ~$25-40/year — still trivial compared to instructor time saved by catching service drift.
