# Lab 13 — DMS console build (replication instance + endpoints + task)

## Objective

Build the AWS Database Migration Service (DMS) infrastructure for a homogeneous MySQL → S3 migration. Provision the replication instance, define source and target endpoints, and create the migration task. **Don't actually start the task** — there's no real source database to migrate from. The point is to experience the DMS wizards and understand what each piece is for; the actual data movement is exercise theatre at this scale and time budget.

## Time budget: 30 minutes

This replaces the prior paper exercise. The 7 Rs design-thinking still happens — the discussion at the end (10 min) uses the same portfolio cards and asks "which strategy fits this workload, and what AWS service implements it?".

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. You need an existing VPC — reuse Lab 1's, or use the default VPC.

## Steps

### 1. Replication instance (5 min to start; ~10 min to provision)

The replication instance is the EC2 that DMS uses to read from source, transform, and write to target. It's the only piece that costs real money in this lab — start it first so it provisions while you do the rest of the steps.

- **AWS DMS → Replication instances → Create replication instance**
- Name: `archadv-<you>-lab13-ri`
- Instance class: **dms.t3.small**
- Engine version: latest
- Allocated storage: 20 GB (default)
- VPC: yours
- Multi-AZ: **Single-AZ** (lab — production would be Multi-AZ)
- Public accessibility: **Yes** (for the lab — production would be No with VPC peering / TGW to source)
- Advanced settings:
  - VPC security group: default (or create new)
  - KMS key: AWS-managed default
- Maintenance: **Don't upgrade automatically**
- Create.

The instance enters `creating` and takes ~10 min to reach `available`. Continue with steps 2-4 while you wait.

### 2. Source endpoint — RDS MySQL (placeholder values; 5 min)

- **DMS → Endpoints → Create endpoint**
- Endpoint type: **Source endpoint**
- Endpoint identifier: `archadv-<you>-lab13-source`
- Source engine: **MySQL**
- Access source: **Provide access information manually**
- Server name: `placeholder.example.com` (we're not testing the connection)
- Port: `3306`
- User name: `dmsuser`
- Password: `placeholder`
- Secure Socket Layer (SSL) mode: `none`
- **Test endpoint connection: skip** (would need a real MySQL on the other end)
- Create endpoint.

Inspect the endpoint after creation — note the **Status: untested** indicator. In production you would test from the replication instance once it's available.

### 3. Target endpoint — S3 (5 min)

S3 is the realistic target for a "lift to data lake" migration pattern.

- **S3 → Create bucket** first: `archadv-<you>-lab13-target`. Block all public access.
- **DMS → Endpoints → Create endpoint**
- Endpoint type: **Target endpoint**
- Endpoint identifier: `archadv-<you>-lab13-target`
- Target engine: **Amazon S3**
- Access role: **Create new IAM role** (or pick existing role with `AmazonS3FullAccess` + DMS trust)
- Service access role ARN: the role you created
- Bucket name: `archadv-<you>-lab13-target`
- Bucket folder: `dms-migration/`
- Other settings: leave defaults (CSV format, no compression)
- Create.

### 4. Database migration task (5 min)

- **DMS → Database migration tasks → Create task**
- Task identifier: `archadv-<you>-lab13-task`
- Replication instance: `archadv-<you>-lab13-ri` (may still be `creating` — that's OK; you can save the task and start it later)
- Source database endpoint: `archadv-<you>-lab13-source`
- Target database endpoint: `archadv-<you>-lab13-target`
- Migration type: **Migrate existing data** (full load only — for the demo; in production you'd choose `Migrate existing data and replicate ongoing changes` for CDC)
- **Editing mode: JSON editor** (so students see what's actually being saved)
- Table mappings: include schema `mydb`, table `%` (wildcard)
- Task settings: defaults (full LOB mode, target-table-prep mode `DROP_AND_CREATE`)
- Migration task startup configuration: **Manually later** (do NOT auto-start)
- Create.

The task enters `Ready` state. It would start replication if the source were real — but ours isn't, so we leave it unstarted.

### 5. Inspect the task configuration (5 min)

- Click into the task.
- **Table mappings** tab — review the JSON. Note the `rule-type: selection` for picking schemas/tables.
- **Migration task assessment** tab — click **Run pre-migration assessment**. (This actually does a structural check; for our placeholder source, it'll likely fail with "cannot connect" — that's the expected outcome and the assessment screen is what students should see.)
- **Logs** tab — empty (task hasn't run).
- **Statistics** tab — empty.

In production, after running the assessment and addressing any blockers, you'd start the task and monitor the **Statistics** tab for row counts, errors, and CDC lag.

## Validation checklist

- [ ] Replication instance reaches `available` within 15 min
- [ ] Source endpoint exists with engine `MySQL`
- [ ] Target endpoint exists with engine `Amazon S3` and points at your bucket
- [ ] IAM role for the S3 endpoint trusts `dms.amazonaws.com` and has S3 access
- [ ] Migration task is in `Ready` state with both endpoints attached and table mappings configured

## Discussion — 7 Rs portfolio (10 min — instructor-led)

Hand out the portfolio cards (Insurance, Healthcare SaaS, or Manufacturing — your choice). For each workload in the portfolio, the room votes on:

1. Which of the 7 Rs is the right strategy?
2. Which AWS service implements that strategy?

Quick reference (the cheat sheet from the original exercise):

| R | Service | Notes |
|---|---|---|
| Retire | n/a | Stop running it |
| Retain | n/a | Leave on-prem |
| Rehost | **AWS MGN** | Lift-and-shift VMs |
| Relocate | VMware Cloud on AWS | Same hypervisor, different host |
| Repurchase | SaaS catalog | Drop + replace |
| Replatform | **DMS / RDS / ElastiCache / MSK** | Rehost + one optimization (this lab's tool) |
| Refactor | Lambda / EKS / Aurora Serverless | Rewrite cloud-native |

The most common mistake in real migrations is **Refactoring everything** — expensive, slow, and the business gets nothing in the meantime. A typical successful migration is 60% Rehost + Replatform.

## Cleanup

In this order:

1. **Database migration task** → Delete (must be `Ready`/`Stopped`, not `Running`).
2. **Endpoints** → Delete both.
3. **Replication instance** → Delete (this is the expensive one — confirm it's gone).
4. **S3 bucket** → Empty + delete.
5. **IAM role for S3 endpoint** → Delete.

## Stretch goals

- Open **DMS Schema Conversion** (formerly the AWS Schema Conversion Tool) and create a migration project that converts a sample MySQL schema to PostgreSQL. Generate the assessment report.
- Open **Application Migration Service (MGN)** in the console. Walk through the agent install instructions for Linux. Don't actually install — just see what students would see if they were rehosting an on-prem VM.
- Compare cost: a 100 GB / 24h DMS migration vs 100 GB / 24h DataSync transfer vs 100 GB / 24h MGN replication. (Hint: DataSync is cheapest, MGN is most expensive but covers OS-level recreation.)
