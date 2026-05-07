
# Lab 5: Transit Gateway with prod/non-prod isolation + S3 VPC endpoint

## Objective

Wire three VPCs to a Transit Gateway using **two TGW route tables** (prod vs non-prod) so that prod-tier VPCs reach shared services but cannot reach the non-prod tier. Then attach an S3 **gateway VPC endpoint** with a restrictive endpoint policy so workloads can reach S3 privately and only the buckets you allow.

## Topology

```
              +---------------------+
              |  Shared-Services    |
              |  VPC (10.0.0.0/16)  |
              +----------+----------+
                         |
                  +------+------+
                  |     TGW     |
                  +------+------+
                  prod-rt   nonprod-rt
                    |             |
        +-----------+--+        +-+-----------+
        | Prod VPC     |        | NonProd VPC |
        | 10.1.0.0/16  |        | 10.2.0.0/16 |
        +--------------+        +-------------+
```

`prod-rt` propagates Prod-VPC + Shared-Services-VPC. `nonprod-rt` propagates NonProd-VPC + Shared-Services-VPC. **Prod-VPC and NonProd-VPC must NOT reach each other.**

## Part A — TGW with two route tables (~35 min)

1. Review the provided Terraform under `Module_05/terraform/`. Note three VPC modules, the TGW, two TGW route tables, and the propagation/association wiring.
2. `terraform init && terraform apply`. Wait for TGW attachments to enter `available` (~3–5 min).
3. Launch an EC2 in each of the three VPCs (provided as part of the apply). Record private IPs.
4. From the **Shared-Services EC2** confirm reachability to both Prod and NonProd EC2s (`ping`, `ssh`).
5. From the **Prod EC2** confirm reachability to Shared-Services. Then attempt to reach NonProd. **It must fail** — that is the validation.
6. From the **NonProd EC2** confirm the mirror behavior — reach Shared-Services, blocked from Prod.
7. If both directions are reachable when they shouldn't be, inspect the TGW route tables: each route table should only have associations + propagations for its tier (prod-rt: prod + shared; nonprod-rt: nonprod + shared).

## Part B — S3 Gateway VPC Endpoint with restrictive endpoint policy (~15 min)

1. Inside the Prod VPC, attach a **gateway VPC endpoint for `com.amazonaws.us-east-1.s3`**. The Terraform creates the endpoint and associates it with the Prod-VPC's private route tables.
2. Inspect the endpoint policy in `terraform/s3_endpoint_policy.json`. It allows `s3:GetObject` and `s3:ListBucket` on the **lab bucket only** (`arn:aws:s3:::archadv-${var.learner}-lab/*`) and denies all other S3 access via the endpoint.
3. From the Prod EC2:
   ```bash
   aws s3 ls s3://archadv-${LEARNER}-lab/    # allowed
   aws s3 ls s3://amazon-reviews-pds/         # denied — endpoint policy blocks
   ```
4. Confirm the deny path: the second command should return `An error occurred (AccessDenied)`.
5. Inspect the route table on the Prod VPC private subnets — note the `pl-...` prefix-list route pointing at the gateway endpoint.

## Validation checklist

- [ ] Prod EC2 ↔ Shared-Services EC2: works
- [ ] NonProd EC2 ↔ Shared-Services EC2: works
- [ ] Prod EC2 → NonProd EC2: **does not** work
- [ ] NonProd EC2 → Prod EC2: **does not** work
- [ ] Prod EC2 → `s3://archadv-<learner>-lab/`: works (via VPC endpoint, not the public internet)
- [ ] Prod EC2 → any other S3 bucket: blocked by endpoint policy
- [ ] Endpoint route present in private subnet route table

## Cleanup

```
terraform destroy
```

## Stretch goals

- Add an interface VPC endpoint for SSM (so you can connect to the EC2s without bastions/SSH).
- Tighten the endpoint policy further with `aws:PrincipalOrgID` so only callers from your AWS Organization can use the endpoint.
- Replicate the gateway endpoint in NonProd-VPC and confirm the policy applies independently per endpoint.
