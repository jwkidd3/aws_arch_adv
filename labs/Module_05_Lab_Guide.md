# Lab 5 — Transit Gateway with prod/non-prod isolation + S3 VPC endpoint

## Objective

Wire three VPCs to a Transit Gateway using **two TGW route tables** (prod vs non-prod) so prod and shared-services can talk and non-prod is isolated from prod. Then attach an **S3 gateway VPC endpoint** with a restrictive endpoint policy so workloads reach S3 privately and only the buckets you allow.

## Time budget: 75 minutes (was 50 — three VPCs, three EC2s, TGW + 2 RTs + 3 attachments + endpoint)

## Topology

```
              +---------------------+
              |  Shared-Services    |
              |  VPC (10.10.0.0/16) |
              +----------+----------+
                         |
                  +------+------+
                  |     TGW     |
                  +------+------+
                  prod-rt   nonprod-rt
                    |             |
        +-----------+--+        +-+-----------+
        | Prod VPC     |        | NonProd VPC |
        | 10.20.0.0/16 |        | 10.30.0.0/16|
        +--------------+        +-------------+
```

`prod-rt` propagates Prod-VPC + Shared-Services-VPC. `nonprod-rt` propagates NonProd-VPC + Shared-Services-VPC. **Prod-VPC and NonProd-VPC must NOT reach each other.**

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. **Check VPC quota.** This lab creates **3 new VPCs**. With the default 5 VPCs/region and the default VPC + your Lab 1 VPC already present, you'll be at the cap. If the instructor pre-raised the quota to 15, you're fine. If not: either ensure all prior-lab VPCs are cleaned up before starting (verify in **VPC → Your VPCs**), or request an increase via **Service Quotas → AWS services → Amazon VPC → VPCs per Region** (auto-approves in minutes).

## Part A — Build the three VPCs (10 min)

For each of three VPCs, use **VPC → Create VPC → VPC and more** with these settings:

| Name | CIDR | Public subnets | Private subnets | NAT |
|---|---|---|---|---|
| `archadv-<you>-prod` | `10.20.0.0/16` | 2 (across 2 AZs) | 2 (across 2 AZs) | None |
| `archadv-<you>-nonprod` | `10.30.0.0/16` | 2 | 2 | None |
| `archadv-<you>-shared` | `10.10.0.0/16` | 2 | 2 | None |

Skip NAT in all three to save cost — we're testing TGW reachability, not internet egress.

Launch one **`t3.micro` EC2 in each VPC's public subnet**, with a public IP. We use public subnets so SSM Agent can reach the SSM service via the IGW (no NAT, no interface endpoints needed).

- Instance profile: create role `archadv-<you>-ssm-ec2` with `AmazonSSMManagedInstanceCore`. Attach during launch.
- Security group: allow **All ICMP - IPv4** from `10.0.0.0/8` (so cross-VPC ping works), allow all traffic from same SG. **Do not** open any port to `0.0.0.0/0` — we connect via Session Manager only.
- Auto-assign public IP: **Enable**.
- Name tags: `prod-ec2`, `nonprod-ec2`, `shared-ec2`.

Wait ~2 min for SSM Agent to register each instance — they appear under **Systems Manager → Session Manager → Start session** once registered.

## Part B — Transit Gateway (10 min)

### 1. Create the TGW

- **VPC → Transit Gateways → Create transit gateway**
- Name: `archadv-<you>-tgw`
- Default association route table: **Disable**
- Default propagation route table: **Disable** (we want manual control)
- Create. Wait ~2 min until `available`.

### 2. Create two TGW route tables

- **VPC → Transit Gateway Route Tables → Create**
- Name 1: `prod-rt` — pick your TGW
- Name 2: `nonprod-rt` — pick your TGW

### 3. Attach all three VPCs to the TGW

For each VPC: **VPC → Transit Gateway Attachments → Create**

- Attachment type: VPC
- Transit Gateway: yours
- VPC: choose
- Subnets: the **private** subnet in each AZ
- Name tag: `prod-attach`, `nonprod-attach`, `shared-attach`

Wait ~3 min until each is `available`.

### 4. Wire the route tables

In **TGW Route Tables → prod-rt**:

- **Associations** tab → Create association → `prod-attach`. (Each attachment can only associate with one route table.)
- **Propagations** tab → Create propagation → `prod-attach` AND `shared-attach`.

In **TGW Route Tables → nonprod-rt**:

- **Associations** tab → Create association → `nonprod-attach`.
- **Propagations** tab → Create propagation → `nonprod-attach` AND `shared-attach`.

(`shared-attach` itself only needs to be associated with one route table — choose `prod-rt`.)

### 5. Add static routes in each VPC's route table

In each of the **three VPCs' private route tables**, add:

| VPC | Destination | Target |
|---|---|---|
| Prod | `10.10.0.0/16` (shared) | TGW |
| Prod | `10.30.0.0/16` (nonprod) | TGW (so the test packet leaves the VPC and reaches the TGW, where prod-rt black-holes it — proving TGW-level isolation, not just VPC-level) |
| NonProd | `10.10.0.0/16` | TGW |
| NonProd | `10.20.0.0/16` | TGW |
| Shared | `10.20.0.0/16` | TGW |
| Shared | `10.30.0.0/16` | TGW |

## Part C — Validate isolation (5 min)

Open **Systems Manager → Session Manager → Start session**, choose each EC2 in turn, and ping:

```bash
# From shared-ec2:
ping -c 3 <prod-ec2-private-ip>     # works
ping -c 3 <nonprod-ec2-private-ip>  # works

# From prod-ec2:
ping -c 3 <shared-ec2-private-ip>   # works
ping -c 3 <nonprod-ec2-private-ip>  # MUST FAIL — that's the validation

# From nonprod-ec2:
ping -c 3 <shared-ec2-private-ip>   # works
ping -c 3 <prod-ec2-private-ip>     # MUST FAIL
```

If both prod ↔ nonprod directions work, your TGW route tables aren't isolating. The most common cause: you propagated `nonprod-attach` into `prod-rt` (or vice-versa). Fix the propagations.

## Part D — S3 Gateway VPC Endpoint (15 min)

### 1. Create a private bucket

- **S3 → Create bucket**: `archadv-<you>-lab`. Block all public access. Tag.
- Upload one file: `lab-object.txt`.

### 2. Create the gateway endpoint in Prod VPC

- **VPC → Endpoints → Create endpoint**
- Service category: AWS services
- Service name: `com.amazonaws.us-east-1.s3` — **type: Gateway**
- VPC: prod
- Route tables: select **all private route tables in prod**
- Policy: **Custom**, paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLabBucket",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject", "s3:ListBucket", "s3:PutObject"],
      "Resource": [
        "arn:aws:s3:::archadv-<you>-lab",
        "arn:aws:s3:::archadv-<you>-lab/*"
      ]
    },
    {
      "Sid": "DenyEverythingElse",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "NotResource": [
        "arn:aws:s3:::archadv-<you>-lab",
        "arn:aws:s3:::archadv-<you>-lab/*"
      ]
    }
  ]
}
```

Replace `<you>` with your name. Create.

### 3. Verify route table

In each prod private route table you selected, confirm a route appears:

```
pl-xxxx (com.amazonaws.us-east-1.s3) → vpce-xxxx
```

Without that route, traffic still leaves via the public path and the endpoint policy never sees it. (No NAT in this VPC, so without the endpoint route the call would fail with a timeout — that's actually a useful diagnostic.)

### 4. Test from `prod-ec2`

In **Systems Manager → Session Manager** on `prod-ec2`:

```bash
# Allowed:
aws s3 ls s3://archadv-<you>-lab/
aws s3 cp s3://archadv-<you>-lab/lab-object.txt -

# Denied by endpoint policy:
aws s3 ls s3://nyc-tlc/
# Expected: An error occurred (AccessDenied) when calling the ListObjectsV2 operation
```

The first command works because the endpoint policy permits it. The second is denied **at the endpoint**, not at IAM — your role has `AdministratorAccess` and could in theory list any bucket, but it can't reach S3 except via this endpoint, and the endpoint denies it.

## Validation checklist

- [ ] Prod EC2 ↔ Shared EC2: works
- [ ] NonProd EC2 ↔ Shared EC2: works
- [ ] Prod EC2 → NonProd EC2: **does not** work
- [ ] NonProd EC2 → Prod EC2: **does not** work
- [ ] Prod EC2 → `s3://archadv-<you>-lab/`: works (via VPC endpoint)
- [ ] Prod EC2 → any other S3 bucket: blocked by endpoint policy
- [ ] Endpoint route present in private subnet route table

## Cleanup

In this order to avoid `DependencyViolation` errors:

1. Terminate the three EC2s.
2. Delete the S3 bucket (empty first).
3. Delete the S3 VPC endpoint.
4. On each TGW route table, **delete its associations and propagations** first (otherwise attachments can't be deleted).
5. Delete the three TGW VPC attachments.
6. Delete the two TGW route tables.
7. Delete the TGW.
8. Delete the three VPCs (use **Delete VPC** to remove subnets/route tables in one shot).

## Stretch goals

- Add an **interface VPC endpoint for SSM** in the prod VPC. Detach the public path entirely (delete the IGW from prod) and confirm Session Manager still works through the SSM endpoints.
- Tighten the endpoint policy with `aws:PrincipalOrgID` so only callers from your AWS Organization can use it (look up your Org ID with the instructor — you can read it from the Sandbox account but not change it).
