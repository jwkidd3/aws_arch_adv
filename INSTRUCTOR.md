# Instructor Guide — Advanced Architecting on AWS (3 days)

This guide is for the person delivering the course. Learners should not see it during class — it contains lab solutions, pacing tells, and shared-account guardrails.

---

## Pre-class checklist (the day before)

- [ ] Shared AWS training account is provisioned with IAM Identity Center; one user per learner
- [ ] Sandbox OU and target sub-account exist for Module 2's scoped exercise (see *Module 2 setup* below)
- [ ] On-prem-simulator VPC exists in a separate region for Module 3 (the "remote site" in the Site-to-Site VPN lab)
- [ ] Each learner has a Cloud9 environment **or** confirmed CloudShell access. Cloud9 closed to new AWS customers in 2024 — verify your account opened before then or fall back to CloudShell.
- [ ] On at least one learner workspace: `bash install_terraform_ubuntu` succeeds, `terraform -v` returns >= 1.6
- [ ] You have one backup workspace ready to hand to a learner whose environment fails irrecoverably
- [ ] Course materials are accessible (private repo learners can `git clone` from inside Cloud9 / CloudShell)
- [ ] Instructor cleanup script tested — keys off `Owner=<learner>` + `Course=archadv` tags
- [ ] Cost guardrail: an account-level Budget alert at 80% of expected daily burn so a runaway lab is caught fast

### Module 2 setup (must be done before class)

Module 2's lab cannot run as written in a single shared account, because each learner cannot create new Organizations / OUs. The workaround:

1. Pre-create an **OU named `archadv-sandbox`** under the org's root.
2. Pre-create one **sub-account per learner** under that OU, named `archadv-<learner>`. Use AWS account closure as cleanup if the training account is purpose-built for this course; otherwise tag for later.
3. Pre-stage a baseline **deny-all-but-approved-regions SCP** detached. Learners attach/detach it during the lab to see SCPs apply.
4. The full Control Tower walkthrough is **demonstrated by the instructor** in a separate management-account console window; learners do not deploy Control Tower themselves.

---

## Pacing tells per module

> **Course-wide ratio target: 30% lecture, 70% lab.** Every module slot is timed at roughly that split. The "lecture" minutes are the absolute maximum — if you finish slides early, hand back the time to the lab. Never the other way around.

### Module 1 — Reviewing Architecting Concepts (25 min teach + 50 min lab)

- WAFR is review for this audience. **25 minutes is enough.** Survey by show-of-hands which pillars learners use today, anchor on the two least-used pillars and the design-principles slide. Skip the per-pillar service-list slides if the room is sharp.
- **Lab 1** runs both Part A (console) and Part B (Terraform); the point is comparing the two flows. With 50 min the room can do both — pairs split the work, then walk each other through.

### Module 2 — Single to Multiple Accounts (25 min teach + 50 min lab)

- Spend disproportionate time on the **OU strategy** slide — this is the durable concept; SCPs are mechanics. Cut the IAM Identity Center deep-dive to a single comparison row.
- **Lab 2** uses the pre-created sandbox OU. Stretch goals (with the extra 20 min vs the old plan): attach a second SCP that denies tag-less resource creation; observe the AccessDenied; then detach and watch normal launches resume. **Do not** let learners try to create new OUs.

### Module 3 — Hybrid Connectivity (25 min teach + 65 min lab)

- The **VPN vs Direct Connect vs Cloud WAN** slide is the pivotal teach moment. After that, hand off into the lab.
- FIPS 140-2 question comes up — short answer: "Direct Connect terminating to a FIPS-validated CGW; for VPN, GovCloud or a customer-managed FIPS appliance on-prem."
- **Lab 3** has the longest lab budget on Day 1 (65 min). Use the spare time for the Route 53 Resolver outbound endpoint section — set up a forwarder and prove `dig host.corp.example.com @<resolver-ip>` returns the on-prem record. That's the "aha" moment.

### Module 4 — Specialized Infrastructure (25 min teach + 50 min lab)

- Survey the room's actual use cases first; deep-dive only the relevant ones (Local Zones, Outposts, Wavelength, Snow). 5G is rarely applicable — keep brief.
- **Lab 4** is File Gateway + DataSync. With 50 min, after the basic transfer add a DataSync schedule and verify the second sync picks up only the deltas — that's the production pattern.

### Module 5 — Connecting Networks (25 min teach + 50 min lab)

- Transit Gateway is the centerpiece. Spend most teaching time on **TGW route tables and propagation** — that's where designs go wrong in the wild. Cut the VPC peering deep-dive to a single comparison slide so the lab fits in 50 min.
- VPC sharing via RAM gets a fast pass — most orgs don't use it.
- **Lab 5** is two-part: Part A (~35 min) is the TGW with prod/non-prod isolation across three VPCs. Part B (~15 min) attaches an S3 gateway VPC endpoint to the prod VPC with a restrictive endpoint policy. The "make non-prod *not* reach prod" ping check and the "any other bucket = AccessDenied" curl are the two validations.
- Walk the room during Part A — pairs that get connectivity but don't validate isolation think they're done.
- Common Part B miss: learners forget to associate the gateway endpoint with the private route tables. The Terraform does this for them, but if they tweak it manually the prefix-list route disappears.

### Module 6 — Containers (25 min teach + 50 min lab)

- ECS vs EKS vs Fargate triangulation — assume some familiarity, focus on **when to pick which**. 25 min is plenty.
- The PDFs in `Module_06/Container/` are deep references; do not read from them in class.
- **Lab 6** builds a container image, pushes to ECR, deploys to ECS Fargate behind an ALB. With 50 min, after the basic deploy run a rolling update with a tag bump and watch the service drain old tasks while bringing up new ones — that's the production pattern they came to learn.
- Common stall: ECR push denied → fix in the per-learner instance profile, not in the lab.

### Module 7 — CI/CD (25 min teach + 65 min lab)

- The deployment-strategies pack is rich — pick **2 strategies** for the teach (rolling + blue/green); the lab does a third.
- CloudFormation discussion: keep the YAML primer to ~5 min — learners know IaC from Terraform.
- **Lab 7** has the longest lab budget on Day 2 (65 min). End-to-end: CodeCommit → CodeBuild → CodeDeploy. With the extra 20 min, switch the deploy strategy to canary and watch the traffic split. Pre-stage the buildspec.yml.

### Module 8 — High Availability & DDoS Protection (25 min teach + 50 min lab)

- The **Shield Standard vs Advanced** distinction is the most-asked-about — Standard is free; Advanced is a $3,000/mo commitment with response-team access. Have the answer ready.
- 25 min teach forces you to skip Network Firewall deep-dive — give it one slide and move on.
- **Lab 8** builds an ALB + ASG with a WAF web ACL containing AWS-managed rule groups. With 50 min, after the SQLi-shape request is blocked, have learners write a **custom rate-based rule** and validate it triggers under repeated requests from a single source.

### Module 9 — Securing Data (25 min teach + 50 min lab)

- 25 min teach: anchor on **key policies vs IAM policies** ("key policy is the source of truth") and the encryption-context use case for envelope encryption. Cut CloudHSM to a single mention.
- **Lab 9** creates a customer-managed KMS key, encrypts an S3 object, stores a DB password in Secrets Manager, rotates it. With 50 min, after rotation observe the new `AWSCURRENT` version and add a custom key policy condition that limits decrypt to a specific IAM role.

### Module 10 — Large-Scale Data Stores (15 min teach + 30 min lab)

- 15 min teach: anchor on the access-pattern decision lens (OLTP / OLAP / event / cache / lake) and the Aurora Global vs DynamoDB Global comparison. Drop the per-engine deep-dive.
- **Lab 10** is S3 + Glue Crawler + Athena. With 30 min, push the Parquet-CTAS stretch goal — re-running the same `GROUP BY` query against the converted table to compare `Data scanned`. That's the data-lake economic argument in numbers.

### Module 11 — Large-Scale Applications (10 min teach + 20 min paired exercise)

- 10 min teach: only the **scaling triggers** slide (CPU / memory / custom CW metric / request count per target) and Route 53 latency-vs-geo. Everything else is exercise.
- **Exercise 11** (paired, 20 min): each pair receives a scenario card and designs the autoscaling triggers + traffic-routing strategy. 12 min pair work, 8 min share-back. Whiteboard or shared doc — no console. Counted as lab time because the room is doing the work.

### Module 12 — Optimizing Cost (15 min teach + 30 min lab)

- 15 min teach: AWS pricing models comparison + tagging-as-foundation. Skip the per-service cost optimization slides — they belong to the relevant module's lab.
- **Lab 12** with 30 min: Cost Explorer saved report grouped by `Course=archadv` tag (instructor demo if account fresh) + a learner-built Budget alarm at $5 with email subscription. Confirm SubscriptionConfirmation arrived. The Budget alarm is the new addition vs the original 15-min plan.

### Module 13 — Migrating Workloads (15 min teach + 30 min paired exercise)

- 15 min teach: drill the **7 Rs** (Retire, Retain, Rehost, Relocate, Repurchase, Replatform, Refactor) and DMS homogeneous vs heterogeneous. Cut the MGN video to 60 seconds.
- **Exercise 13** (paired, 30 min): pairs receive a workload portfolio card (e.g., "Java 8 monolith on RHEL + Oracle 11g + Tomcat fleet + 50TB SAN backups"). Pick a strategy per workload and justify. 20 min pair work, 10 min share-back. Counted as lab time.

### Module 14 — Capstone (25 min framing + 50 min build/walkthrough)

- **25 min framing/recap**: scenario brief (lab guide), course recap mapped to the capstone components (which module each piece comes from), questions before they pair up.
- **50 min build/walk**: 15 min architecture diagram in pairs → 25 min partial Terraform reuse from earlier modules → 10 min walkthroughs.
- **Realistic outcome**: learners leave with a diagram + Terraform that runs `init`+`plan` cleanly + one or two open decisions identified. That is success. Do not push for a fully-applied stack.

---

## Lab solutions & expected outcomes

> Hide this section in any printed handout. These are answer keys.

### Lab 1 — Well-Architected VPC

Console build typically takes 10–15 min for this audience. Terraform build takes 2 min after `init`. The validation step (SSH to the EC2 in the public subnet) catches missing-IGW-route mistakes — that's the most common error.

### Lab 2 — Organizations / SCP

Expected sequence:
1. Switch role into the sandbox sub-account (`archadv-<learner>`) via IAM Identity Center.
2. Try to launch an EC2 in `eu-west-1` — succeeds.
3. Instructor (in management account) attaches the deny-all-but-approved-regions SCP to the sandbox OU.
4. Learner retries the EC2 launch in `eu-west-1` — denied. Tries `us-east-1` — succeeds.
5. Detach SCP. Confirm `eu-west-1` works again.

The "aha" moment is the deny propagating without the learner doing anything in their account.

### Lab 3 — VPN + Route 53 Resolver

Tunnel typically establishes in 5–10 min after `apply`. If it stays `DOWN` after 15 min, check:
- Customer Gateway public IP matches the simulated on-prem VPC's NAT/EIP
- Pre-shared key matches on both sides
- BGP ASNs are different on each side

Route 53 Resolver outbound endpoint forwards `corp.example.com` (the simulated on-prem zone) to the on-prem VPC's Route 53 Private Hosted Zone. Validation: `dig host.corp.example.com @<resolver-ip>` from the workload VPC returns the on-prem record.

### Lab 4 — Storage Gateway + DataSync

The file gateway VM (Storage Gateway as EC2 AMI) takes ~5 min to activate. DataSync transfer of the seed files is < 1 min. Validation: files visible in S3 under the destination prefix.

### Lab 5 — TGW + S3 VPC endpoint

**Part A (TGW isolation):** common mistake is attaching all three VPCs to the same TGW route table and not noticing the lack of isolation. The fix is **two TGW route tables** (`prod-rt` and `nonprod-rt`) with selective associations and propagations. The validation checklist:
- Prod-VPC ↔ Shared-Services-VPC: works
- NonProd-VPC ↔ Shared-Services-VPC: works
- Prod-VPC ↔ NonProd-VPC: **does not** work

**Part B (S3 gateway endpoint):** the endpoint policy in the Terraform allows `s3:GetObject`, `s3:ListBucket`, `s3:PutObject` on the learner's lab bucket only and an explicit deny on every other bucket. From the prod EC2:
- `aws s3 ls s3://archadv-<learner>-lab/` → succeeds
- `aws s3 ls s3://amazon-reviews-pds/` → `An error occurred (AccessDenied)`

If the deny does not fire: check that the gateway endpoint is associated with the prod private route tables (look for the `pl-...` prefix-list route). If the route is missing, S3 traffic is leaving via the public path and the endpoint policy never sees it.

### Lab 6 — Container build & deploy

Image builds in 90–120 sec. ECR push takes 30 sec. ECS service stabilizes (target=1, healthy=1) in ~3 min. Validation: `curl <ALB-DNS>` returns the container's hello payload.

If ECR push gets `denied: requested access to the resource is denied`, the Cloud9 instance profile is missing ECR perms. Fix in the per-learner role; not in the lab.

### Lab 7 — CI/CD pipeline

Expected first build time: 4–6 min total. Stages:
1. Source (CodeCommit pull): instant
2. Build (CodeBuild image build + push): 2–3 min
3. Deploy (CodeDeploy to existing ECS service from Lab 6): 1–2 min

If the pipeline fails at Build with `permission denied` writing to the artifact bucket, fix the CodeBuild service role's S3 perms. Pre-bake.

### Lab 8 — WAF + ALB + ASG

Trigger blocks via:
```bash
curl "http://<alb-dns>/?id=1' OR '1'='1"
```
WAF logs the block in 1–2 min. The CloudWatch metric `BlockedRequests` for the web ACL ticks up.

### Lab 9 — KMS + Secrets Manager

Encrypt-then-fetch flow:
```bash
aws s3 cp test.txt s3://<bucket>/encrypted/ --sse aws:kms --sse-kms-key-id <key-arn>
aws s3 cp s3://<bucket>/encrypted/test.txt -
```
Rotation: the Secrets Manager secret has an attached rotation Lambda; manual rotation succeeds in < 30 sec. Verify the new version is `AWSCURRENT`.

### Lab 10 — Data lake (S3 + Glue + Athena)

The Terraform provisions:
- `archadv-<learner>-datalake` bucket with two seed CSVs under `sales/year=2024/`
- Glue catalog database `archadv_<learner>_db`
- Glue Crawler `archadv-<learner>-sales-crawler` with `AWSGlueServiceRole` + S3 read on the lake bucket
- Athena workgroup `archadv-<learner>-wg` with results written to a separate bucket

Expected sequence:
1. `terraform apply -var "learner=<name>"` — ~90 sec
2. Run the crawler in the Glue console — ~60 sec to `Ready`
3. Confirm the `sales` table appears with columns `order_id, region, product, quantity, revenue` and partition key `year`
4. Run the GROUP BY revenue query in Athena — returns 4 rows (us-east, us-west, eu-west, ap-south)
5. Drop a third CSV; re-run crawler; re-run query — totals change

Common stalls:
- Athena says `Table not found`: the crawler hasn't been run yet. Push the learner to the Glue console.
- Crawler reports `Access Denied`: the Glue role's S3 read policy didn't apply. `terraform apply` again or add the inline policy in the console.
- `terraform destroy` refuses to delete the bucket: contents remain. `aws s3 rm s3://archadv-<learner>-datalake/ --recursive`, then re-destroy.

### Lab 12 — Cost Explorer

No Terraform; pure console exercise. Learners build a saved report grouped by tag `Course=archadv` with a daily granularity. Catch: Cost Explorer needs ~24 hours of data — if the training account is fresh, demo from the instructor's account instead.

### Capstone — verification

Acceptance bar (any of the following counts as success):
- Working diagram covering VPC, ALB, ASG, Aurora, S3, CloudFront, WAF
- Terraform that runs `init` + `plan` cleanly (apply not required to pass)
- Walkthrough explains *why* each component was chosen, with one trade-off identified

---

## Common gotchas across the course

| Symptom | Where seen | Fix |
|---|---|---|
| Cloud9 onboarding blocked | Day 1 setup | Account is a post-2024 onboard; switch to CloudShell or pre-provisioned EC2 dev box |
| `terraform apply` hangs on VPN tunnel | Lab 3 | Tunnel is in `PENDING_INGRESS` — wait, don't kill. AWS-side BGP can take 10 min |
| ECR push denied | Lab 6, Lab 7 | Cloud9 instance profile lacks ECR perms — fix in per-learner role, not in lab |
| Pipeline build stage fails | Lab 7 | CodeBuild role missing S3 artifact bucket perms; or buildspec.yml typo |
| WAF rule not blocking | Lab 8 | Rule group attached but ALB → web ACL association missing; or evaluation order |
| KMS access denied | Lab 9 | Key policy doesn't grant the calling principal — key policies override IAM allows |
| Cost Explorer empty | Lab 12 | New account; no data yet. Demo from instructor account |
| Resources orphaned post-class | All labs | Run cleanup script keyed on `Owner=<learner>` and `Course=archadv` tags |

---

## Time-flex levers

If running ahead of schedule:
- Add 10 min to Module 2's discussion of OU design strategies
- Demo Direct Connect virtual interfaces in Module 3 (not in lab; instructor-only walk)
- Add a second deployment strategy to Lab 7 (canary in addition to rolling)
- Have learners present their Module 10 / 11 design to the room (instead of pair-share only)

If running behind:
- Skip Lab 1 Part A (console steps) — go straight to Terraform
- Cut Module 4's 5G/Wavelength sub-slides
- Skip Lab 12 — just demo Cost Explorer instead of having learners build the saved report
- Compress Module 13 to 30 min by cutting MGN demo
- Capstone: deliver as a 60-min design exercise with no Terraform applied

If a learner falls behind:
- Pair them with someone ahead — works for Labs 1, 5, 6, 8
- For Labs 2 and 3 (where the AWS-side timing dominates) walk them through personally; the wait time is the same
- Hand them the Capstone reference Terraform if they're stuck for >15 min — they still benefit from running it

---

## Final-day close

After capstone walkthroughs:

1. One sentence per learner: "the one architecture decision I'm changing Monday."
2. Point at this guide's `Module 2 setup` section — anyone running this internally needs it.
3. Done.

No formal wrap-up slides. The capstone *is* the close.
