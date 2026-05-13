# Extras — out-of-scope reference material

This folder holds material that is **not part of the course** but was inherited from earlier versions of the repo. It's kept for instructor reference only; students never see it.

## Contents

| Directory | What |
|---|---|
| `cross_account_terraform/` | Terraform example using `assume_role` provider to operate in a different AWS account. Demonstrates the cross-account pattern from the management account into a Sandbox. |
| `centralized_terraform_example/` | Multi-provider Terraform setup (dev/staging/prod aliases via assume_role) across three Sandbox accounts. |
| `terraform_org_info/` | Tiny wrapper that runs `aws organizations list-accounts` via local-exec. |

## Note

The Advanced Architecting course is **console-driven**; Terraform belongs to a separate course in the portfolio. The examples here are vestigial — not referenced by any student-facing material. They embed real Sandbox account IDs; either update those if you reuse the examples, or delete the folder entirely.
