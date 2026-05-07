# Automation — proof harness for the lab guides

This subtree is **instructor-side infrastructure**. It is **not** part of the student-facing course materials. Students never see this directory; they work in the AWS console per the lab guides under `Module_NN/labs/`.

The goal is to detect AWS service drift between class deliveries before students hit it. Every lab that has a meaningful API surface gets a Terraform module that builds the same end-state the lab guide describes, plus a `validate.sh` that asserts the lab's validation checklist via the AWS CLI. CI runs them weekly in a dedicated CI Sandbox account.

Yes, the irony is intentional: the course is intentionally Terraform-free for students, and the harness is Terraform. The harness is plumbing, not pedagogy.

## What it catches

- Deprecated APIs and removed services (e.g., DataSync agent below `m5.2xlarge` floor)
- Renamed managed policies and AMI deprecations
- Service quotas that have shrunk
- Regional availability changes
- IAM permissions drift on managed roles
- The exact 6 critical blockers that the May 2026 doc-check pass found

## What it doesn't catch

- AWS console UI reorganization (button labels, menu paths) — only humans catch that. The labs link to AWS docs where possible to limit exposure.
- Time-budget realism — only end-to-end execution by a real human proves that.
- Pedagogy — does the "aha" land? Field test only.
- Anything that depends on instructor-side state (Module 3 simulator, Module 2 SCP attach from management).

## Layout

```
automation/
├── README.md                  this file
├── proof-harness/             one directory per lab
│   ├── lab-01-vpc/            full implementation
│   ├── lab-04-storage-gw/     stub (TODO)
│   ├── lab-05-tgw/            full implementation
│   ├── lab-06-ecs/            stub
│   ├── lab-07-cicd/           stub
│   ├── lab-08-alb-asg-waf/    stub
│   ├── lab-09-kms-secrets/    full implementation
│   ├── lab-10-data-lake/      stub
│   └── lab-12-budgets/        stub
└── tools/
    ├── run-harness.sh         orchestrate one lab end-to-end
    ├── cleanup.sh             tag-keyed nuker (safety net after CI)
    ├── ami-resolver.sh        validate AMI references in lab guides resolve
    └── doc-link-check.sh      validate AWS doc URLs in lab guides

.github/workflows/
├── validate-labs.yml          weekly cron + manual trigger
└── lint-docs.yml              PR checks (doc links, AMI refs, markdown)
```

## Labs **without** harnesses (and why)

| Lab | Why no harness |
|---|---|
| Lab 2 (Org/SCP) | The student-facing flow is observation-only. The instructor-side SCP attach lives in the management account, which CI does not have access to. |
| Lab 3 (VPN) | Hard dependency on the instructor's on-prem simulator, which is by design out of scope for student-side automation. The AWS-side resources (CGW, VGW, VPN connection) are validated by the cleanup script's resource-shape audit. |
| Lab 11 / Lab 13 | Paper exercises. Nothing to deploy. |
| Lab 14 (capstone) | Open-ended design exercise. Validating "did the design make sense" is a human job. |

## How to run locally

Prerequisites: Terraform >= 1.6, AWS CLI v2, `jq`, an AWS profile with credentials in a Sandbox account that can create the resources for the lab in question.

```bash
cd automation/proof-harness/lab-01-vpc
terraform init
terraform apply -auto-approve
./validate.sh
terraform destroy -auto-approve
```

Or use the orchestrator (handles apply → validate → destroy with cleanup as safety net):

```bash
automation/tools/run-harness.sh lab-01-vpc
```

## How to run in CI

CI uses GitHub Actions OIDC to assume a role in a dedicated CI Sandbox account. You need to do one-time setup:

1. Create an IAM role in the CI Sandbox: `archadv-ci-harness`. Trust policy: GitHub OIDC for the repo. Permissions: broad (`PowerUserAccess` is fine for a Sandbox).
2. Add `AWS_HARNESS_ROLE_ARN` as a GitHub Actions secret with the role ARN.
3. The weekly cron in `.github/workflows/validate-labs.yml` does the rest.

Estimated CI cost: **$5–10 / week** for the full set serialized. Each harness applies, asserts, and destroys within ~15 min wall clock.

## Adding a new lab harness

1. `cp -r automation/proof-harness/lab-01-vpc automation/proof-harness/lab-NN-newthing`
2. Edit `main.tf` to build the same end-state the lab guide describes
3. Edit `validate.sh` to assert each item in the lab's "Validation checklist"
4. Edit `outputs.tf` to expose the values `validate.sh` needs
5. Add `lab-NN-newthing` to the matrix in `.github/workflows/validate-labs.yml`
6. Run `automation/tools/run-harness.sh lab-NN-newthing` locally to confirm it works

## Honest caveat

The harness validates services and IAM and quotas. It does **not** validate the student-facing console click-paths. A lab can pass CI and still have stale console wording. The remaining 20–30% confidence comes from the instructor's pre-class dry-run.
