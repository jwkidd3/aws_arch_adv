# Instructor Guide — Advanced Architecting on AWS (3 days)

This guide is for the person delivering the course. Students should not see it during class — it contains lab solutions, pacing tells, and Org-side setup notes.

This is a **console-driven, concept-focused** course. Students do not write Terraform — that lives in a separate Terraform course. The single permitted Terraform cameo is in Module 14's capstone, and even there the student's primary task is design and console exploration, not `terraform apply`.

---

## Lab validation status (May 2026)

The 14 lab guides were doc-validated against current AWS console and service behavior in May 2026, and patched for the issues found. Items below still require **live confirmation in your pre-class dry-run** — AWS console wording shifts continuously and a few of these are simulator-dependent.

| Lab | Confirm in dry-run |
|---|---|
| Lab 1 | NAT EIP release works during cleanup; no quota issue |
| Lab 2 | SCP attach/propagation timing in *your* org (typically <30 sec) |
| Lab 3 | Lab 3 is configure-only (no simulator). Tunnels stay `DOWN` by design. Validation focuses on AWS-side resource creation. |
| Lab 4 | DataSync agent boots on `m5.2xlarge`; File Gateway 150 GiB cache disk attached at launch |
| Lab 5 | EC2s in **public subnets** so SSM Agent reaches SSM via IGW (private subnets without endpoints don't work); ping isolation matches the validation table |
| Lab 6 | **Lab 1 VPC** is used (default VPC has only public subnets and breaks Step 6) |
| Lab 7 | `pip3 install --user git-remote-codecommit` works in CloudShell; `git clone codecommit::us-east-1://...` succeeds (the older `aws codecommit credential-helper` does NOT work with IAM Identity Center sessions) |
| Lab 8 | "Override all rule actions to: Block" is set on each managed rule group; SQLi probe returns 403 |
| Lab 9 | S3 default encryption with **Bucket Key disabled** (lab requires it for the `kms:ViaService` deny test); SAR rotation Lambda deploys before being attached to Secrets Manager |
| Lab 10 | Athena workgroup result location set; Glue database name is hyphen-free |
| Lab 12 | Member-account access to Cost Explorer (or fall back to Budgets-only path) |
| Lab 14 | Aurora "kick off and move on" framing matches reality; CloudFront distribution propagation is acceptable |

**Time-budget note:** the lab guides now show realistic budgets (Labs 3, 4, 5 increased to 75/70/75 min, exceeding the schedule's 65/50/50 slots). Three options when this happens in class: (a) run over and adjust the next break, (b) drop the stretch goals and tail steps to stay in slot, (c) move slower labs to time-flex windows. The original `## Time budget` line in each lab guide reflects "how long this really takes," not the slot allocation.

## Pre-class checklist (the day before)

- [ ] Shared AWS Organization is operational; IAM Identity Center is enabled in the management account
- [ ] Sandbox OU exists under the Org root
- [ ] One Sandbox member account per student (`Sandbox1` … `SandboxN`) exists under the Sandbox OU
- [ ] **Per-student starter credential** in the mgmt account `001613358280` — gives the student enough access to create their own IAM Identity Center user (Lab 1 Part A). Easiest: an IAM user per student with `AWSSSOMemberAccountAdministrator` (managed policy) + an inline policy permitting `sso:CreateUser` and `sso:CreateAccountAssignment` on the student's assigned Sandbox. Hand out username + initial password.
- [ ] **`AdministratorAccess` permission set exists** in IAM Identity Center (this is the AWS-managed predefined permission set; Lab 1 Part A assigns it to the student's Sandbox)
- [ ] **`DenyOutsideApprovedRegions` SCP is attached to the Sandbox OU before class** (it's the steady state students observe in Lab 2). The optional detach/re-attach demo is instructor-led if time allows.
- [x] Module 3 simulator: **NOT NEEDED** — Lab 3 was pivoted to configure-only on 2026-05-12. Students build all AWS-side hybrid resources and observe the `DOWN` state; no IPsec responder required. See updated Module 3 lab guide.
- [ ] Per-account Budget alarm in each Sandbox at $10/day; instructor email subscribed
- [ ] **VPC quota — recommended raise to 15 in each Sandbox.** The default 5/region *technically fits* the course (Lab 5 peak = default + Lab-1-style VPC + 3 Lab-5 VPCs = exactly 5) but only with perfect cleanup discipline; one stale VPC from Module 4 troubleshooting and Lab 5 fails at apply with `VpcLimitExceeded`. Raising to 15 via Service Quotas → "VPCs per Region" is free, auto-approves in minutes, and removes the class-blocker risk. Skip it only if you trust your students' cleanup discipline. Optional: delete the default VPC in each Sandbox to free another slot.
- [ ] Cleanup script keyed on `Owner=<student>` + `Course=archadv` tags is tested
- [ ] **VPC continuity: locked in — Lab 1's VPC stays up for the full course.** Confirmed 2026-05-12. Students do NOT delete the VPC at any point during class. Cost: NAT Gateway ~$0.045/hr × 24h × 3 nights = ~$3/student (~$81 for 27 students). After class ends, you (the instructor) clean up VPCs centrally across all Sandboxes — Lab 1 / Lab 3 / etc. cleanup sections in the lab guides only direct students to remove the per-lab compute (EC2s, NAT-attached EIPs are kept) so the VPC stays available for the next lab.
- [ ] AWS access portal URL + per-student credentials packet is ready to distribute

### Org structure at a glance

```
Root
├── Management account (instructor only — IAM IdC, Org trail, SCPs)
├── Security OU
│   ├── Audit account                  (used for Module 9 Org-trail demo)
│   └── Log Archive account            (used for Module 9 Org-trail demo)
└── Sandbox OU
    ├── Sandbox1                       (student 1)
    ├── Sandbox2                       (student 2)
    └── Sandbox<N>
```

### Module 2 setup (must be done before class)

Module 2's lab cannot have students create new top-level Org structure (only the management account can). The flow:

1. **Pre-class**: instructor attaches the `DenyOutsideApprovedRegions` SCP to the Sandbox OU. It stays attached for the duration of Lab 2 (and beyond).
2. **In class — students** sign into their Sandbox, try a service in `eu-west-1` → `UnauthorizedOperation`. Try the same in `us-east-1` and `us-east-2` → succeeds. Try a third region (e.g., `ca-central-1`) → also denied.
3. **Optional instructor-led demo** (if time allows): detach the SCP live, students retry `eu-west-1` → now succeeds. Re-attach, the deny returns. This shows the propagation effect — Org-level controls applied or removed instantly across every student's account without anyone doing anything in their own account.

#### The exact SCP staged in this Org

Policy name: **`DenyOutsideApprovedRegions`**. Approved regions: `us-east-1` and `us-east-2`. `NotAction` excludes global services (IAM, Organizations, STS, billing, CloudFront, Route 53, etc.) so the deny only kicks in for regional services in non-approved regions.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyOutsideApprovedRegions",
      "Effect": "Deny",
      "NotAction": [
        "iam:*", "organizations:*", "sts:*", "support:*", "account:*",
        "billing:*", "ce:*", "budgets:*", "cloudfront:*", "route53:*",
        "route53domains:*", "globalaccelerator:*", "networkmanager:*",
        "waf:*", "shield:*", "health:*", "tag:*", "trustedadvisor:*",
        "pricing:*", "ec2:DescribeRegions"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": ["us-east-1", "us-east-2"]
        }
      }
    }
  ]
}
```

### Module 3 setup (no pre-class work needed)

**Updated 2026-05-12:** Lab 3 is now **configure-only** — students build the AWS-side hybrid networking resources (CGW, VGW, Site-to-Site VPN, Route 53 Resolver outbound endpoint, forwarding rule) and observe the `DOWN` tunnel state, but no IPsec responder is required. Students use placeholder values (`203.0.113.10` peer IP, `archadv-lab3-2026` PSK, ASN 65000, etc.) defined in the lab guide.

The teaching point shifts from "see the tunnel come UP" to "see exactly what AWS provides to a hybrid customer, including the downloaded vendor-specific config that an on-prem network engineer would paste into their router." Lab time reduced from 75 to 50 min.

If you want to restore the original simulator-based flow (instructor running libreswan + FRR + BIND on a single EC2), see the lab guide version prior to commit on 2026-05-12.

---

## Pacing tells per module

> **Course-wide ratio target: 30% lecture, 70% lab.** Every module slot is timed at roughly that split. The "lecture" minutes are the absolute maximum — if you finish slides early, hand back the time to the lab. Never the other way around.

### Module 1 — Reviewing Architecting Concepts (15 min teach + 60 min lab)

- WAFR is review for this audience. **25 minutes is enough.** Survey by show-of-hands which pillars learners use today, anchor on the two least-used pillars and the design-principles slide. Skip the per-pillar service-list slides if the room is sharp.
- **Lab 1** is a console-only Well-Architected VPC build. With 50 min, students can complete the full multi-AZ public/private build, NAT, route tables, and validate via SSH from a public-subnet EC2. Walk the room — common mistakes are missing IGW route in the public route table and NAT in the public subnet (not the private subnet).

### Module 2 — Single to Multiple Accounts (20 min teach + 55 min lab)

- Spend disproportionate time on the **OU strategy** slide — this is the durable concept; SCPs are mechanics. Cut the IAM Identity Center deep-dive to a single comparison row.
- **Lab 2**: students experience their Sandbox account from the inside, then watch a live SCP attach/detach from the management account. The "aha" is *not* the SCP itself — it's that the deny propagated without the student touching their account. Stretch goal: instructor attaches a tag-required SCP, students try untagged launches, see deny, then succeed when tags are added.

### Module 3 — Hybrid Connectivity (25 min teach + 50 min lab)

- The **VPN vs Direct Connect vs Cloud WAN** slide is the pivotal teach moment. After that, hand off into the lab.
- FIPS 140-2 question comes up — short answer: "Direct Connect terminating to a FIPS-validated CGW; for VPN, GovCloud or a customer-managed FIPS appliance on-prem."
- **Lab 3 is configure-only as of 2026-05-12.** Students build all AWS-side hybrid resources (CGW, VGW, VPN, Resolver outbound, forwarding rule) using placeholder on-prem values from the lab guide. The tunnel stays `DOWN` because there's no IPsec responder — that's the teaching point. Have students inspect the **Download configuration** vendor file from the Tunnel details tab as the "aha" moment — it's the exact config an on-prem engineer would feed into their router.
- The 5-min wrap-up discussion (Step 8) is where Direct Connect, the missing on-prem side, and CloudWatch tunnel metrics get covered.

### Module 4 — Specialized Infrastructure (25 min teach + 50 min lab)

- Survey the room's actual use cases first; deep-dive only the relevant ones (Local Zones, Outposts, Wavelength, Snow). 5G is rarely applicable — keep brief.
- **Lab 4** is File Gateway + DataSync — both deployed in the student's Sandbox account using the EC2-hosted gateway pattern. With 50 min, after the basic transfer add a DataSync schedule and verify the second sync picks up only the deltas.
- The Storage Gateway VM (deployed as an EC2 AMI inside the Sandbox) takes ~5 min to activate. Have students start that step early and pivot to slide review while it activates.

### Module 5 — Connecting Networks (25 min teach + 50 min lab)

- Transit Gateway is the centerpiece. Spend most teaching time on **TGW route tables and propagation** — that's where designs go wrong in the wild. Cut the VPC peering deep-dive to a single comparison slide.
- VPC sharing via RAM gets a fast pass — most orgs don't use it.
- **Lab 5** is two-part: Part A (~35 min) is the TGW with prod/non-prod isolation across three VPCs (all built in the student's Sandbox account). Part B (~15 min) attaches an S3 gateway VPC endpoint to the prod VPC with a restrictive endpoint policy. The "make non-prod *not* reach prod" ping check and the "any other bucket = AccessDenied" CloudShell test are the two validations.
- Walk the room during Part A — pairs that get connectivity but don't validate isolation think they're done.
- Common Part B miss: students forget to **associate the gateway endpoint with the private route tables**. Without that, S3 traffic leaves via the public path and the endpoint policy never sees it.

### Module 6 — Containers (25 min teach + 50 min lab)

- ECS vs EKS vs Fargate triangulation — assume some familiarity, focus on **when to pick which**. 25 min is plenty.
- **Lab 6** builds a container image (in CloudShell), pushes to ECR, deploys to ECS Fargate behind an ALB. With 50 min, after the basic deploy run a rolling update with a tag bump and watch the service drain old tasks while bringing up new ones — that's the production pattern they came to learn.
- Common stall: ECR push denied → student is logged into the wrong account. They should be in their Sandbox account, not management. Confirm by checking the IAM IdC role badge in the top-right.

### Module 7 — CI/CD (25 min teach + 65 min lab)

- The deployment-strategies pack is rich — pick **2 strategies** for the teach (rolling + blue/green); the lab does a third.
- CloudFormation discussion: keep the YAML primer to ~5 min — students may know IaC from the dedicated Terraform course; the goal here is "what does the AWS-native option look like".
- **Lab 7** has the longest lab budget on Day 2 (65 min). End-to-end: CodeCommit → CodeBuild → CodeDeploy. With the extra 20 min, switch the deploy strategy to canary and watch the traffic split. Pre-stage a starter `buildspec.yml` template the student copies in.

### Module 8 — High Availability & DDoS Protection (20 min teach + 55 min lab)

- The **Shield Standard vs Advanced** distinction is the most-asked-about — Standard is free; Advanced is a $3,000/mo commitment with response-team access. Have the answer ready.
- 25 min teach forces you to skip Network Firewall deep-dive — give it one slide and move on.
- **Lab 8** builds an ALB + ASG with a WAF web ACL containing AWS-managed rule groups. With 50 min, after the SQLi-shape request is blocked, have students write a **custom rate-based rule** and validate it triggers under repeated requests from a single source.

### Module 9 — Securing Data (25 min teach + 50 min lab)

- 25 min teach: anchor on **key policies vs IAM policies** ("key policy is the source of truth") and the encryption-context use case for envelope encryption. Cut CloudHSM to a single mention.
- **Lab 9** creates a customer-managed KMS key, encrypts an S3 object, stores a DB password in Secrets Manager, rotates it. With 50 min, after rotation observe the new `AWSCURRENT` version and add a custom key policy condition that limits decrypt to a specific IAM role.
- Optional Org-trail demo: instructor shows the Org-level CloudTrail in the Audit account (concept only — students don't have access).

### Module 10 — Large-Scale Data Stores (15 min teach + 30 min lab)

- 15 min teach: anchor on the access-pattern decision lens (OLTP / OLAP / event / cache / lake) and the Aurora Global vs DynamoDB Global comparison. Drop the per-engine deep-dive.
- **Lab 10** is S3 + Glue Crawler + Athena, all in the Sandbox account console. With 30 min, push the Parquet-CTAS stretch goal — re-running the same `GROUP BY` query against the converted table to compare `Data scanned`. That's the data-lake economic argument in numbers.

### Module 11 — Large-Scale Applications (10 min teach + 25 min hands-on lab + 5 min discussion)

- 10 min teach: only the **scaling triggers** slide (CPU / memory / custom CW metric / request count per target) and Route 53 latency-vs-geo.
- **Lab 11** (25 min hands-on): students build ALB + ASG with target tracking on `ALBRequestCountPerTarget`, generate load via `ab` from CloudShell, watch the ASG scale from 2 to 3-4 instances. Validates the *behavior* of "scale on the right metric."
- **5 min discussion** at the end: hand out the scenario cards (spiky news site, internal HR app, real-time game, batch image, IoT) and walk through which trigger fits each — this preserves the design-thinking that the prior paper exercise emphasized.
- Slot is 30 min total; if the teach finishes early, hand the time to the lab. If the lab runs long, cut the optional scale-down step.

### Module 12 — Optimizing Cost (15 min teach + 30 min lab)

- 15 min teach: AWS pricing models comparison + tagging-as-foundation. Skip the per-service cost optimization slides — they belong to the relevant module's lab.
- **Lab 12** with 30 min: Cost Explorer saved report grouped by `Course=archadv` tag (instructor demo from management account if Sandboxes are fresh) + a student-built Budget alarm at $5 with email subscription. Confirm the SubscriptionConfirmation arrives.

### Module 13 — Migrating Workloads (15 min teach + 30 min hands-on lab + 10 min discussion)

- 15 min teach: drill the **7 Rs** (Retire, Retain, Rehost, Relocate, Repurchase, Replatform, Refactor) and DMS homogeneous vs heterogeneous. Cut the MGN video to 60 seconds.
- **Lab 13** (30 min hands-on): students build a complete DMS pipeline (replication instance + source MySQL endpoint + S3 target endpoint + migration task) but **do not start the task** — there's no real source DB. The pre-migration assessment failure is the validation of "you'd really want this to run before promoting to prod."
- **10 min discussion** at the end: portfolio-card walkthrough (Insurance / Healthcare SaaS / Manufacturing) — pairs pick strategy + AWS service per workload. Preserves the 7 Rs design-thinking the prior paper exercise emphasized.
- **Cost watch:** the dms.t3.small replication instance is ~$0.07/hr while running. With cleanup at slot end, ~$0.05/student total. Across 27 students: ~$1.35.

### Module 14 — Capstone (20 min framing + 55 min build/walkthrough)

- **25 min framing/recap**: scenario brief (lab guide), course recap mapped to the capstone components (which module each piece comes from), questions before they pair up.
- **50 min build/walk**: 15 min architecture diagram in pairs → 25 min console build of the highest-priority pieces (VPC + ALB + ASG, or VPC + RDS + S3 + CloudFront — pair chooses) → 10 min walkthroughs.
- Optional Terraform reference: Module 14 retains a small Terraform starter (`Module_14/terraform/`) for students who already took the dedicated Terraform course and want to see the equivalent IaC. Do not lecture on it.
- **Realistic outcome**: students leave with a diagram + console-built proof-of-concept covering 2–3 tiers + one or two open decisions identified. That is success. Do not push for a fully-deployed multi-tier app.

---

## Lab solutions & expected outcomes

> Hide this section in any printed handout. These are answer keys.

### Lab 1 — Well-Architected VPC

Console build typically takes 25–35 min for this audience. The validation step (SSH to the EC2 in the public subnet) catches missing-IGW-route mistakes — that's the most common error. Confirm the public subnet has the IGW route (`0.0.0.0/0 → igw-...`) and the private subnet has the NAT route (`0.0.0.0/0 → nat-...`).

### Lab 2 — Organizations / SCP

Expected sequence:
1. Student is signed into their Sandbox account via IAM IdC.
2. Student tries to launch an EC2 in `eu-west-1` — succeeds.
3. **Instructor (in management account) attaches the staged `DenyOutsideApprovedRegions` SCP to the Sandbox OU.**
4. Student retries the EC2 launch in `eu-west-1` — denied. Tries `us-east-1` — succeeds.
5. Instructor detaches the SCP. Student confirms `eu-west-1` works again.

The "aha" moment is the deny propagating without the student doing anything in their account. Run this live as a synchronized class demo — count down "3, 2, 1, attached" and have everyone retry simultaneously.

### Lab 3 — VPN + Route 53 Resolver

Tunnel typically establishes in 5–10 min after the student creates the VPN connection. If it stays `DOWN` after 15 min, check:

- Customer Gateway public IP matches the simulator's NAT/EIP (instructor distributes this)
- Pre-shared key matches the one in the credentials packet
- BGP ASNs are different on each side (Sandbox-side is the AWS-default 64512; on-prem simulator is 65000)

Route 53 Resolver outbound endpoint forwards `corp.example.com` to the simulator. Validation: `dig host.corp.example.com @<resolver-ip>` from the Sandbox CloudShell returns the on-prem record.

### Lab 4 — Storage Gateway + DataSync

The File Gateway VM (deployed as Storage Gateway EC2 AMI inside the Sandbox) takes ~5 min to activate. DataSync transfer of the seed files is < 1 min. Validation: files visible in the destination S3 bucket under the configured prefix.

### Lab 5 — TGW + S3 VPC endpoint

**Part A (TGW isolation):** common mistake is attaching all three VPCs to the same TGW route table and not noticing the lack of isolation. The correct design is **two TGW route tables** (`prod-rt` and `nonprod-rt`) with selective associations and propagations:

| Route table | Associates | Propagates |
|---|---|---|
| `prod-rt` | Prod VPC, Shared-Services VPC | Prod, Shared-Services |
| `nonprod-rt` | NonProd VPC | NonProd, Shared-Services |

The validation checklist:
- Prod-VPC ↔ Shared-Services-VPC: works
- NonProd-VPC ↔ Shared-Services-VPC: works
- Prod-VPC ↔ NonProd-VPC: **does not** work

**Part B (S3 gateway endpoint):** the endpoint policy allows `s3:GetObject`, `s3:ListBucket`, `s3:PutObject` on the student's lab bucket only and an explicit deny on every other bucket. From a Prod-VPC EC2 (or CloudShell launched in the Prod VPC):

- `aws s3 ls s3://archadv-<student>-lab/` → succeeds
- `aws s3 ls s3://amazon-reviews-pds/` → `An error occurred (AccessDenied)`

If the deny does not fire: check that the gateway endpoint is associated with the prod private route tables (look for the `pl-...` prefix-list route). If the route is missing, S3 traffic is leaving via the public path and the endpoint policy never sees it.

### Lab 6 — Container build & deploy

Image builds (in CloudShell) in 90–120 sec. ECR push takes 30 sec. ECS service stabilizes (target=1, healthy=1) in ~3 min. Validation: `curl <ALB-DNS>` returns the container's hello payload.

If ECR push gets `denied: requested access to the resource is denied`, the student is in the wrong account or the IAM IdC role didn't propagate. Have them re-fetch credentials from the access portal (the AWS CLI v2 SSO refresh button).

### Lab 7 — CI/CD pipeline

Expected first build time: 4–6 min total. Stages:

1. Source (CodeCommit pull): instant
2. Build (CodeBuild image build + push): 2–3 min
3. Deploy (CodeDeploy to existing ECS service from Lab 6): 1–2 min

If the pipeline fails at Build with `permission denied` writing to the artifact bucket, fix the CodeBuild service role's S3 perms in IAM. Pre-bake a working starter for the role.

### Lab 8 — WAF + ALB + ASG

Trigger blocks via CloudShell or browser:
```bash
curl "http://<alb-dns>/?id=1' OR '1'='1"
```
WAF logs the block in 1–2 min. The CloudWatch metric `BlockedRequests` for the web ACL ticks up.

### Lab 9 — KMS + Secrets Manager

Encrypt-then-fetch flow (CloudShell):
```bash
aws s3 cp test.txt s3://<bucket>/encrypted/ --sse aws:kms --sse-kms-key-id <key-arn>
aws s3 cp s3://<bucket>/encrypted/test.txt -
```
Rotation: the Secrets Manager secret has an attached rotation Lambda; manual rotation succeeds in < 30 sec. Verify the new version is `AWSCURRENT`.

### Lab 10 — Data lake (S3 + Glue + Athena)

Expected sequence (all in console + CloudShell inside the Sandbox account):

1. Student creates S3 bucket and uploads two seed CSVs under `sales/year=2024/`
2. Student creates Glue catalog database `archadv_<student>_db`
3. Student creates IAM role for Glue (`AWSGlueServiceRole` + S3 read on the lake bucket)
4. Student creates and runs Glue Crawler — ~60 sec to `Ready`
5. Confirm the `sales` table appears with columns `order_id, region, product, quantity, revenue` and partition key `year`
6. Student creates Athena workgroup pointed at a results bucket
7. Run the GROUP BY revenue query in Athena — returns 4 rows (us-east, us-west, eu-west, ap-south)
8. Drop a third CSV; re-run crawler; re-run query — totals change

Common stalls:
- Athena says `Table not found`: the crawler hasn't been run yet. Push the student to the Glue console.
- Crawler reports `Access Denied`: the Glue role's S3 read policy is missing. Add the inline policy.
- `aws s3 rb` refuses: contents remain. `aws s3 rm s3://archadv-<student>-datalake/ --recursive`, then retry.

### Lab 12 — Cost Explorer

Pure console exercise. Students build a saved report grouped by tag `Course=archadv` with daily granularity and a $5 Budget with email alert. Catch: Cost Explorer needs ~24 hours of data — if the Sandbox accounts are fresh, demo the saved report from the management account and have students focus on the Budget alarm + email subscription confirmation.

### Capstone — verification

Acceptance bar (any of the following counts as success):

- Working diagram covering VPC, ALB, ASG, Aurora (or RDS), S3, CloudFront, WAF
- Console-built proof-of-concept covering at least 2 tiers (e.g., ALB + ASG, or RDS + S3) inside the student's Sandbox account
- Walkthrough explains *why* each component was chosen, with one trade-off identified

Optional: a student who already took the Terraform course may opt to build instead via the Module 14 Terraform reference. This is a stretch path, not a requirement.

---

## Common gotchas across the course

| Symptom | Where seen | Fix |
|---|---|---|
| "I can't see resource X" | Any lab | Student switched to the wrong account in IAM IdC. Check the role badge top-right; should read `AWSAdministratorAccess @ Sandbox<N>` |
| `AccessDenied` in `eu-west-1` | Module 2 (during/after demo) | Region SCP is still attached. Detach from Sandbox OU |
| VPN tunnel stuck `DOWN` | Lab 3 | Wrong PIP or PSK from credentials packet; or simulator-side BGP. AWS-side BGP can take 10 min |
| ECR push denied | Lab 6, Lab 7 | Wrong account or stale IAM IdC creds — re-fetch from access portal |
| Pipeline build stage fails | Lab 7 | CodeBuild role missing S3 artifact bucket perms; or `buildspec.yml` typo |
| WAF rule not blocking | Lab 8 | Rule group attached but ALB → web ACL association missing; or evaluation order wrong |
| KMS access denied | Lab 9 | Key policy doesn't grant the calling principal — key policies override IAM allows |
| Cost Explorer empty | Lab 12 | New account; no data yet. Demo from management account |
| Resources orphaned post-class | All labs | Run cleanup script keyed on `Owner=<student>` and `Course=archadv` tags across every Sandbox account |

---

## Time-flex levers

If running ahead of schedule:

- Add 10 min to Module 2's discussion of OU design strategies; demo Control Tower from the management account (instructor-only walk)
- Demo Direct Connect virtual interfaces in Module 3 (concept only — not in any Sandbox)
- Add a second deployment strategy to Lab 7 (canary in addition to rolling)
- Have students present their Module 10 / 11 design to the room (instead of pair-share only)

If running behind:

- Skip the second SCP in Lab 2 (tag-required); just do the region-restriction one
- Cut Module 4's 5G/Wavelength sub-slides
- Skip Lab 12 — just demo Cost Explorer from the management account instead of having students build the saved report
- Compress Module 13 to 30 min by cutting MGN demo
- Capstone: deliver as a 60-min design exercise with no console build

If a student falls behind:

- Pair them with someone ahead — works for Labs 1, 5, 6, 8
- For Labs 2 and 3 (where the AWS-side timing dominates) walk them through personally; the wait time is the same
- For the Capstone, have them pair with someone whose design is further along

---

## Final-day close

After capstone walkthroughs:

1. One sentence per student: "the one architecture decision I'm changing Monday."
2. Point at this guide's *Pre-class checklist* — anyone running this internally needs it.
3. Done.

No formal wrap-up slides. The capstone *is* the close.
