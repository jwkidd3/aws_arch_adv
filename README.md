# Advanced Architecting on AWS

Three-day, introductory-level architecting course aligned with the AWS *Advanced Architecting on AWS* curriculum. Each module presents a scenario with an architectural challenge and walks through AWS services and features as solutions.

## Audience

- Cloud architects
- Solutions architects
- Anyone designing solutions for cloud infrastructures

## Prerequisites

- Working knowledge of core AWS services across Compute, Storage, Networking, and IAM
- Prior attendance of *Architecting on AWS* (or equivalent experience)
- At least one year of operating AWS workloads
- Comfortable in a Linux shell (the labs use Cloud9 / CloudShell terminals and Terraform)

## Course outcomes

By the end of the course, participants will be able to:

- Apply the AWS Well-Architected Framework to evaluate and improve workloads
- Centralize permissions across multiple accounts using AWS Organizations, OUs, SCPs, and IAM Identity Center
- Design hybrid networks using Site-to-Site VPN, Client VPN, Direct Connect, and Route 53 Resolver
- Connect VPCs at scale using Transit Gateway, VPC sharing (RAM), and interface/gateway endpoints
- Build and deploy containerized workloads on ECS, Fargate, and ECR
- Wire a CI/CD pipeline using CodePipeline, CodeBuild, CodeDeploy, and CloudFormation
- Defend public workloads with WAF, Shield, AWS Network Firewall, and Firewall Manager
- Protect data with KMS, Secrets Manager, and CloudHSM
- Choose appropriate large-scale data stores and design for elasticity at the application tier
- Optimize cost with Cost Explorer, Budgets, Savings Plans, and right-sizing
- Plan a workload migration using the 7 Rs framework, AWS MGN, DMS, and DataSync
- Synthesize the above in a capstone design project

## Schedule

Each day runs **9:00–4:00**, with lunch 12:00–1:00 and two 15-minute breaks.
Net working time: **5.5 hrs/day = 16.5 hrs total**.

### Day 1 — Foundations, multi-account, hybrid

| Time | Slot |
|---|---|
| 9:00 – 9:15 | Welcome, intros, AWS environment access |
| 9:15 – 10:30 | **Module 1** *Reviewing Architecting Concepts* (25) + **Lab 1** Well-Architected VPC (50) |
| 10:30 – 10:45 | Break |
| 10:45 – 12:00 | **Module 2** *Single to Multiple Accounts* (25) + **Lab 2** Organizations / SCP / IAM Identity Center (50) |
| 12:00 – 1:00 | **Lunch** |
| 1:00 – 2:30 | **Module 3** *Hybrid Connectivity* (25) + **Lab 3** Site-to-Site VPN + Route 53 Resolver (65) |
| 2:30 – 2:45 | Break |
| 2:45 – 4:00 | **Module 4** *Specialized Infrastructure* (25) + **Lab 4** Storage Gateway + DataSync (50) |

### Day 2 — Networks, containers, CI/CD, HA & DDoS

| Time | Slot |
|---|---|
| 9:00 – 9:15 | Day 1 recap, Q&A |
| 9:15 – 10:30 | **Module 5** *Connecting Networks* — Transit Gateway, VPC endpoints, RAM (25) + **Lab 5** TGW + S3 VPC endpoint (50) |
| 10:30 – 10:45 | Break |
| 10:45 – 12:00 | **Module 6** *Containers* — ECS, Fargate, ECR (25) + **Lab 6** Build & deploy a container (50) |
| 12:00 – 1:00 | **Lunch** |
| 1:00 – 2:30 | **Module 7** *CI/CD* — CodePipeline / CodeBuild / CodeDeploy / CloudFormation (25) + **Lab 7** Pipeline (65) |
| 2:30 – 2:45 | Break |
| 2:45 – 4:00 | **Module 8** *High Availability & DDoS Protection* — WAF, Shield, Network Firewall, Firewall Manager (25) + **Lab 8** WAF + ALB + ASG (50) |

### Day 3 — Securing data, scale, cost, migration, capstone

| Time | Slot |
|---|---|
| 9:00 – 9:15 | Day 2 recap, Q&A |
| 9:15 – 10:30 | **Module 9** *Securing Data* — KMS, Secrets Manager, CloudHSM (25) + **Lab 9** KMS + Secrets Manager (50) |
| 10:30 – 10:45 | Break |
| 10:45 – 11:30 | **Module 10** *Large-Scale Data Stores* — Aurora, DynamoDB, data lake patterns (15) + **Lab 10** S3 + Glue + Athena data lake (30) |
| 11:30 – 12:00 | **Module 11** *Large-Scale Applications* — multi-tier, autoscaling, geo-routing (10) + **Exercise 11** paired scaling-design (20) |
| 12:00 – 1:00 | **Lunch** |
| 1:00 – 1:45 | **Module 12** *Optimizing Cost* — Cost Explorer, Budgets, Savings Plans (15) + **Lab 12** Cost Explorer + Budgets (30) |
| 1:45 – 2:30 | **Module 13** *Migrating Workloads* — 7 Rs, MGN, DMS, DataSync (15) + **Exercise 13** paired 7Rs walkthrough (30) |
| 2:30 – 2:45 | Break |
| 2:45 – 4:00 | **Module 14** *Capstone Project* — framing (25) + design + build + walkthrough (50) |

> **Lecture / lab split:** every module is paced at roughly **30% lecture, 70% lab**. Across the course this works out to ~305 min lecture and ~640 min lab (≈ 32 / 68). Modules 11 and 13 do not deploy infrastructure; their "lab" half is a structured paired design exercise (scaling design, 7 Rs walkthrough) — counted as lab time because it is learner-driven activity. The capstone in Module 14 is the integrative hands-on close.

## Repository layout

```
aws_arch_adv/
├── Module_00/        Instructor reference Terraform — multi-account scaffolding
├── Module_01/ … Module_14/
│   ├── slides/       Module slide deck
│   ├── labs/         Lab guide (md + pdf)
│   └── terraform/    Lab Terraform starter
├── install_terraform_ubuntu   One-liner Terraform install for Cloud9 / CloudShell
├── README.md         This file
└── INSTRUCTOR.md     Instructor-only — pacing notes, lab solutions, gotchas
```

## Required environment

This course is designed to run inside a **shared AWS training account** with one workspace per learner.

### Per-learner workspace (recommended)

- **AWS Cloud9** environment if the training account supports it
  - Suggested instance: `t3.medium` on Amazon Linux 2023
  - Each learner names their environment `archadv-<your-name>`
  - Cloud9 onboarding closed to new AWS customers in 2024 — see fallback below
- **Fallback if Cloud9 is unavailable:** AWS CloudShell (region-attached, free) or a local terminal with the AWS CLI configured against issued credentials. CloudShell lacks long-running session persistence; for the longer Terraform applies (Modules 5, 7, 8) instructors should pre-warm a backup workspace.
- Terraform installed via `bash install_terraform_ubuntu` (Cloud9 / CloudShell on AL2023 use the equivalent `dnf` form; see `INSTRUCTOR.md`).

### Per-learner IAM

The shared account must provide each learner with a named IAM user (or IAM Identity Center user) and a role bundle granting:

- VPC / EC2 / EBS / EFS full access (scoped to a learner-prefixed name pattern via tag-based conditions where possible)
- Transit Gateway, VPC peering, RAM (Module 5)
- ECR, ECS, Fargate (Module 6)
- CodeCommit / CodePipeline / CodeBuild / CodeDeploy, CloudFormation, S3 artifact bucket (Module 7)
- WAF, Shield Standard, CloudFront, ALB (Module 8)
- KMS create/use, Secrets Manager, IAM PassRole for service roles (Module 9)
- Aurora / DynamoDB read-write to learner-prefixed resources (Modules 10–11)
- Cost Explorer & Budgets read (Module 12)
- DataSync, Storage Gateway, MGN read (Modules 4, 13)

A starting permissions boundary policy is included as commentary in `Module_00/cross_account_terraform/`.

### Shared-account guardrails

- Each learner uses a unique resource prefix (their first name + lab number) so resources are easy to identify and clean up
- Tag every Terraform resource with `Owner=<learner>` and `Course=archadv` — instructor cleanup script keys off these tags
- Module 2 (Organizations / Control Tower) cannot create new top-level org structures inside the shared training account. Learners run a **scoped sub-exercise** in a sandbox OU the instructor pre-creates; full Control Tower walkthrough is demonstrated, not deployed by each learner. See `INSTRUCTOR.md` for the pre-class setup.

## Instructor pre-work

Before learners sign in:

1. Provision the shared training account; distribute the sign-in URL and per-learner IAM Identity Center credentials.
2. Pre-create the sandbox OU and target sub-account used in Module 2's scoped exercise.
3. Pre-create the on-prem-simulator VPC for Module 3 (Site-to-Site VPN endpoint).
4. Provision one Cloud9 (or confirm CloudShell access) per learner; verify Terraform installs cleanly.
5. Run a smoke test of the capstone Terraform from the instructor workstation.
6. Distribute these materials (e.g., push to a private repo learners can `git clone` from inside Cloud9).

## Notes for instructors

- All hands-on builds use Terraform — every module's `terraform/` directory is a runnable starter. Learners are expected to read the HCL, not just `apply` it.
- Lab guides (`labs/Module_NN_Lab_Guide.md`) are intentionally short — they prescribe the *what*, the slides supply the *why*, and the instructor fills the *how* live.
- Modules 10, 11, and 13 ship with outline-only labs (no detailed step-by-step). Run them as paired design exercises with whiteboard / digital diagram, not as console walkthroughs. This is reflected in the schedule.
- Use the on-screen timer for breaks (~15 min mid-morning and mid-afternoon, lunch midday).
- The capstone closes the course. Learners should leave with a working diagram and partially-applied Terraform, not necessarily a fully-deployed stack — the design decisions matter more than the final `apply`.
