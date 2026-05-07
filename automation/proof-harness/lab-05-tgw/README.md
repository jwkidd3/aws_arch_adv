# Lab 5 proof harness

Builds: 3 VPCs (prod / nonprod / shared) + Transit Gateway with two route tables (`prod-rt`, `nonprod-rt`) + 3 attachments + S3 gateway VPC endpoint with a restrictive policy on the prod VPC.

## What it asserts

Connectivity matrix (via SSM `send-command` on the EC2s):

- shared ↔ prod: **reachable**
- shared ↔ nonprod: **reachable**
- prod ↔ nonprod: **isolated** (TGW black-holes traffic via the prod-rt / nonprod-rt segregation)

S3 endpoint policy:

- `s3 ls s3://<lab-bucket>/` from prod-ec2: **allowed**
- `s3 ls s3://nyc-tlc/` from prod-ec2: **denied** (`AccessDenied`)

## Cost (approximate, per harness run)

- Transit Gateway: $0.05/hr
- 3 TGW attachments: $0.05/hr each = $0.15/hr
- 3 EC2 `t3.micro`: ~$0.03/hr
- 6 subnets, 6 RTs, S3 bucket, S3 endpoint: free

Per run (~25 min wall clock for apply + assertions + destroy): **~$0.10**. Weekly CI: ~$5/year.

## Why public subnets here

The student lab guide originally used private subnets. The validation pass found that without NAT or SSM interface endpoints, SSM agent can't reach the SSM service from a private subnet, so Session Manager fails. The patched lab moved EC2s to public subnets with restrictive SGs (no public ingress, only ICMP from `10.0.0.0/8`). The harness mirrors that.

## Why the cross-VPC routes

To prove **TGW-level** isolation rather than just VPC-level, both prod and nonprod VPCs have static routes pointing the *other* tier's CIDR at the TGW. Without those, `ping` would fail at the VPC route table — that's not the test we want. With the routes, the packet leaves the VPC, hits the TGW, and the TGW black-holes it because `prod-rt` doesn't propagate `nonprod-attach`. That black-hole is the assertion.
