# Lab 10 proof harness — STUB

**Status: not yet implemented.**

## Scope when implemented

- Provision the data lake S3 bucket with two seed CSVs under `sales/year=2024/`
- Provision a Glue catalog database (with hyphen-stripped name)
- Provision the IAM role for Glue (`AWSGlueServiceRole` + S3 read inline)
- Provision the Glue Crawler pointed at `sales/`
- Trigger the crawler via API and wait for `Ready` state
- Provision an Athena workgroup pointed at a results bucket
- Submit the SELECT query via Athena API and validate row count + result shape

## Validation

- Crawler runs successfully (status `Ready`, no errors)
- `sales` table appears in catalog with expected columns + `year` partition key
- Athena query returns 4 region rows
- Drop a third CSV via API, re-run crawler, re-run query — totals change

## Why this is not implemented in the initial harness

This lab's API surface is well-suited to automation (every step has a stable API). Implement next after the foundation is proven — high value, low risk.

Copy `lab-09-kms-secrets/` as the template (similar shape — a bucket + IAM + a service that consumes the bucket).
