# Advanced Architecting on AWS

Three-day, introductory-level architecting course aligned with the AWS *Advanced Architecting on AWS* curriculum. Each module presents a scenario with an architectural challenge and walks through AWS services and features as solutions.

**Delivery model:** the course is **console-driven**. Students work in the AWS Management Console inside an **AWS Organization**, with each student assigned their own member account. There is a separate Terraform course; this course does not teach Terraform. (One optional Terraform cameo may appear on Day 3 in the capstone — see Module 14.)

## Audience

- Cloud architects
- Solutions architects
- Anyone designing solutions for cloud infrastructures

## Prerequisites

- Working knowledge of core AWS services across Compute, Storage, Networking, and IAM
- Prior attendance of *Architecting on AWS* (or equivalent experience)
- At least one year of operating AWS workloads
- Comfortable navigating the AWS Management Console

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

## Lab environment — shared AWS Organization

The course runs inside a **single shared AWS Organization** owned by the instructor. Layout:

- **Management account** — owned by the instructor. Hosts the Organization, IAM Identity Center, Control Tower (if enabled), Org-level CloudTrail, Service Control Policies. Students never sign in here directly — instructor demos Org-level concepts from this account in front of the room.
- **Sandbox OU** — one OU under the Org root.
- **Sandbox accounts** — one per student, named `Sandbox1`, `Sandbox2`, … `SandboxN`. Each student is granted an IAM Identity Center user that maps to `AWSAdministratorAccess` in their assigned account only. Students do all hands-on lab work inside their sandbox account.
- **Shared/Support accounts (optional)** — `Audit` and `Log Archive` accounts under a Security OU, used for the Module 9 (CloudTrail Org trail) and Module 12 (consolidated billing) demos.

> **Sign-in flow for students:** On Day 1, students start with **starter credentials** to the management account (instructor pre-stages one per student). Lab 1 Part A walks them through creating their own IAM Identity Center user and assigning `AdministratorAccess` to their Sandbox. From that point on, the sign-in is: AWS access portal URL → their own IdC user → choose `Sandbox<N>` → `AdministratorAccess` → "Open AWS console". Same flow real customers use, but students own their identity end-to-end.

## Schedule

Each day runs **9:00–4:00**, with lunch 12:00–1:00 and two 15-minute breaks.
Net working time: **5.5 hrs/day = 16.5 hrs total**.

### Day 1 — Foundations, multi-account, hybrid

| Time | Slot |
|---|---|
| 9:00 – 9:15 | Welcome, intros, AWS access portal sign-in to assigned Sandbox account |
| 9:15 – 10:30 | **Module 1** *Reviewing Architecting Concepts* (15) + **Lab 1** Identity Center user + Well-Architected VPC (60) |
| 10:30 – 10:45 | Break |
| 10:45 – 12:00 | **Module 2** *Single to Multiple Accounts* (20) + **Lab 2** Organizations / SCP / IAM Identity Center (55) |
| 12:00 – 1:00 | **Lunch** |
| 1:00 – 2:30 | **Module 3** *Hybrid Connectivity* (25) + **Lab 3** Site-to-Site VPN + Route 53 Resolver (50) |
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
| 2:45 – 4:00 | **Module 8** *High Availability & DDoS Protection* — WAF, Shield, Network Firewall, Firewall Manager (20) + **Lab 8** WAF + ALB + ASG (55) |

### Day 3 — Securing data, scale, cost, migration, capstone

| Time | Slot |
|---|---|
| 9:00 – 9:15 | Day 2 recap, Q&A |
| 9:15 – 10:30 | **Module 9** *Securing Data* — KMS, Secrets Manager, CloudHSM (25) + **Lab 9** KMS + Secrets Manager (50) |
| 10:30 – 10:45 | Break |
| 10:45 – 11:30 | **Module 10** *Large-Scale Data Stores* — data lake patterns (10) + **Lab 10** S3 + Glue + Athena data lake (35) |
| 11:30 – 12:05 | **Module 11** *Large-Scale Applications* — scaling triggers (5) + **Lab 11** ASG with custom CloudWatch metric scaling (30) |
| 12:05 – 1:00 | **Lunch** |
| 1:00 – 1:30 | **Module 12** *Optimizing Cost* — Cost Explorer, Budgets, Savings Plans (15) + **Lab 12 — instructor demo only** (15) |
| 1:30 – 2:30 | **Module 13** *Migrating Workloads* — 7 Rs, MGN, DMS, DataSync (15) + **Lab 13** DMS console build (no task start) (30) |
| 2:30 – 2:45 | Break |
| 2:45 – 4:00 | **Module 14** *Capstone Project* — framing (20) + design + build + walkthrough (55) |

> **Lecture / lab split:** every module is paced at **30% lecture, 70% lab**. Module 1 trims its lecture to 15 min (Lab 1 includes a 10-min Identity Center user-creation step in Part A); Modules 2, 8, and 14 trim their lecture to 20 min to keep the ratio honest. **Day 3 schedule notes:** Lab 12 is delivered as a 15-min instructor demo (Cost Explorer is mgmt-account-only; Budgets is a 4-click flow with low hands-on payoff for the time cost). The Module 11 and Module 13 design-discussion tails are absorbed into lecture framing rather than separate segments — keeps Day 3 within the 5.5-hour working budget. The capstone in Module 14 is the integrative close.

## Repository layout

```
aws_arch_adv/
├── labs/                   Module_01..13 lab guides (single-file HTML, console-driven)
├── presentations/          Reveal.js slide decks for Modules 1–13 (single-file HTML)
├── Module_14/              Capstone — kept as a folder because it includes a Terraform reference
│   ├── labs/Module_14_Lab_Guide.html
│   ├── slides/module-14-capstone.html
│   └── terraform/main.tf   optional Day-3 IaC reference for students from the Terraform course
├── extras/                 Inherited Terraform reference material — not part of the course
├── README.md               This file
└── INSTRUCTOR.md           Instructor-only — pacing notes, lab solutions, gotchas
```

## Required environment

### Per student

- AWS access portal URL + IAM Identity Center username/password (instructor distributes on Day 1).
- Modern browser (Firefox or Chrome). The course is 100% console; no local CLI install required.
- Optional: AWS CloudShell within the assigned Sandbox account for the few labs that benefit from CLI validation (Modules 5, 9, 10). Pre-installed in every account; no setup.

### Per Sandbox account (Sandbox1 … SandboxN)

Each student's Sandbox account is provisioned with `AWSAdministratorAccess` for that student. Service-quota notes:

- VPC, EC2, EBS, EFS — default quotas are sufficient
- Transit Gateway (Module 5), VPCs > 5 (Module 5) — confirm regional quota in `us-east-1` before class
- ECS Fargate, ECR (Module 6) — default quotas are sufficient
- CodePipeline, CodeBuild, CodeDeploy, S3 (Module 7)
- WAF, CloudFront, ALB (Module 8)
- KMS, Secrets Manager (Module 9)
- Aurora, DynamoDB (Module 10) — default quotas are sufficient
- Cost Explorer, Budgets (Module 12) — Cost Explorer needs ~24 hours of data; if Sandbox accounts are fresh, demo from the management account
- DataSync, Storage Gateway (Modules 4, 13)

### Shared-Org guardrails (instructor side, in management account)

- Service Control Policy denying regions outside an approved list (default: `us-east-1`, `us-east-2`) attached to the Sandbox OU. Module 2 lab attaches/detaches a stricter SCP for the demo.
- Account-level Budget alarm in each Sandbox at $10/day (configurable) — instructor receives the notification.
- Tag policy requiring `Owner=<student>` and `Course=archadv` on taggable resources where supported.
- Cleanup script keyed on `Owner=<student>` and `Course=archadv` tags, run after class to nuke residual resources.

## Instructor pre-work

Before learners sign in:

1. Provision (or reuse) the shared Organization. Confirm IAM Identity Center is enabled in the management account.
2. Pre-create the Sandbox OU and one Sandbox account per student (`Sandbox1` … `SandboxN`). Use Account Factory in Control Tower if available; otherwise create accounts manually under the Sandbox OU.
3. Create one IAM Identity Center user per student. Assign each user `AWSAdministratorAccess` to their Sandbox account only.
4. Stage the `DenyOutsideApprovedRegions` SCP on the Sandbox OU (detached) for Module 2.
5. Pre-create the on-prem-simulator VPC for Module 3 (Site-to-Site VPN endpoint) — see INSTRUCTOR.md for the exact build.
6. Set the per-account daily Budget alarm in each Sandbox.
7. Distribute the access portal URL + per-student credentials.

## Notes for instructors

- This is a **concept and console** course. The student's hands stay on a browser. Do not introduce Terraform, CDK, or CloudFormation flows in class — the dedicated Terraform course covers IaC.
- Lab guides (`labs/Module_NN_Lab_Guide.md`) are intentionally short — they prescribe the *what*, the slides supply the *why*, the instructor fills the *how* live.
- Modules 11 and 13 are paired design exercises (no console build). Use whiteboard or shared diagram tool.
- Use the on-screen timer for breaks (~15 min mid-morning and mid-afternoon, lunch midday).
- The capstone closes the course. Module 14 may include a brief Terraform reference for engineers who took the separate Terraform course; it is optional and not required to pass.
