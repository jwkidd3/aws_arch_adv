# Lab 4 proof harness (lightweight)

## Scope

This is a **lightweight** harness — it validates the things that change (AMIs, managed policies, instance-type availability) without launching real Storage Gateway or DataSync agent EC2s.

**What it does:**
- Resolves `aws-storage-gateway-*` AMI and `aws-datasync-*` AMI in `us-east-1`
- Creates an S3 bucket with SSE-S3 + public access blocked
- Creates the Storage Gateway IAM role + S3 inline policy
- Confirms `m5.2xlarge` (DataSync minimum) is offered in the region

**What it does NOT do:**
- Launch a Storage Gateway EC2 (~$0.012/hr for `m5.xlarge`)
- Launch a DataSync agent EC2 (~$0.024/hr for `m5.2xlarge`)
- Activate the gateway (HTTP-based handshake is awkward to script)
- Create an actual NFS file share or DataSync task

The end-to-end activation flow is covered by the instructor pre-class dry-run. This harness catches the AWS-side drift items that have hit the validation pass:

- Storage Gateway AMI deprecation
- DataSync minimum instance type changes
- IAM principal trust changes for `storagegateway.amazonaws.com`
- Region-level capacity issues for `m5.2xlarge`

## Cost (approximate, per harness run)

S3 bucket: free for this size. IAM: free. Data sources: free.

Per run: **< $0.001**. Weekly CI: < $0.10/year.
