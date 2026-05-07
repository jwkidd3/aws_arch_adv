# Lab 4 proof harness — STUB

**Status: not yet implemented.**

## Scope when implemented

- Provision the destination S3 bucket
- Provision the File Gateway VM as EC2 (`m5.xlarge` per current minimum) with a 150 GiB cache volume
- Provision a DataSync agent VM as EC2 (`m5.2xlarge` per current minimum)
- Skip the actual gateway *activation* step (it requires a console-side activation key handshake that's painful to script; assert the EC2s boot and the AMIs resolve)
- Validate that an NFS file share can be created (API-only)
- Validate DataSync source + destination locations and a task can be created
- Validate `m5.2xlarge` is the minimum that boots (the central blocker the validation pass found)

## Lower-cost alternative

If the cost of two `m5.xlarge`-class EC2s is unacceptable for weekly CI ($0.40-0.60/run), constrain to:

1. AMI resolution check (does the Storage Gateway AMI still resolve in this region?)
2. IAM managed-policy check (`AWSGlueServiceRole`-equivalent for Storage Gateway)
3. Quota check (can this Sandbox launch `m5.2xlarge`?)

Skip the actual EC2 launch. Rely on instructor dry-run for the remainder.

## Why this is not implemented in the initial harness

Storage Gateway activation is the longest path in the lab and is largely instructor-pre-flight territory. The 6 critical blockers fixed in May 2026 are all asserted by the lab guide patch (cache disk in launch step, agent type bump). A weekly CI would mostly re-confirm those didn't regress, at substantial cost.

If you want it built, copy `lab-01-vpc/` as the template and add the Storage Gateway resources.
