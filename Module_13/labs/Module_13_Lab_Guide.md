# Exercise 13 — Paired migration design (7 Rs walkthrough)

## Objective

Apply the **7 Rs migration framework** (Retire, Retain, Rehost, Relocate, Repurchase, Replatform, Refactor) to a portfolio of real-shape workloads. The point is to practice making *the right* call per workload, not the *one* call.

## Time budget: 30 minutes

- 20 min — pair work
- 10 min — share-back

## Setup

Pair up. Each pair gets a **portfolio card** from the instructor. Sample portfolios:

### Portfolio A — Mid-size insurance company

| # | Workload | Notes |
|---|---|---|
| 1 | Java 8 monolith on RHEL 6 | 50K LOC; original devs gone; runs ~300 customers; mission-critical |
| 2 | Oracle 11g database | 4 TB; some PL/SQL stored procs; tied to workload #1 |
| 3 | 12 Tomcat servers serving customer portal | Load-balanced; 100 req/sec average |
| 4 | Lotus Notes / Domino email | 1,200 users; vendor support ends in 18 months |
| 5 | Internal Wiki on Confluence (self-hosted) | 8 GB content; 200 users |
| 6 | 50 TB SAN backup of file shares | Mostly cold; some files unused for years |
| 7 | Custom .NET CRM (in-house) | 8 years of business logic; integrates with #1 |
| 8 | Crystal Reports server | Used for monthly board pack |

### Portfolio B — Healthcare SaaS startup

| # | Workload | Notes |
|---|---|---|
| 1 | Patient portal (Node.js, Postgres) | 30K patients; HIPAA in scope; 99.9% target |
| 2 | Document store (NFS server, 8 TB) | Patient PDFs; growing 10%/year |
| 3 | Reporting BI (Tableau Server) | Internal analysts; 50 dashboards |
| 4 | Legacy claims system (COBOL on AIX) | One vendor maintains; nobody internal |
| 5 | Data warehouse (Postgres, 2 TB) | Loaded nightly via batch ETL |
| 6 | DevOps Jenkins server | Single server; Jenkins 2.x |
| 7 | Active Directory + DNS | On-prem; 200 staff |

### Portfolio C — Manufacturing co.

| # | Workload | Notes |
|---|---|---|
| 1 | SAP ERP | Production system; SAP-certified support contract |
| 2 | Plant-floor MES on Windows Server 2008 | Air-gapped; OT/IT boundary |
| 3 | Engineering CAD file server | 30 TB; engineers complain about latency |
| 4 | Sharepoint 2013 intranet | 500 staff use it 10 min/week |
| 5 | Crystal Reports server | Quarterly only |
| 6 | Jenkins on a single Linux box | DevOps team of 3 |
| 7 | Email server (Exchange 2016) | 600 mailboxes |

## Deliverable (whiteboard or shared doc)

For each workload, fill in:

| Workload | Strategy (one of 7 Rs) | Target AWS service / pattern | Why this strategy | Key risk |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |

The five-minute summary you'll deliver at share-back: "Of these N workloads, we'd Retire X, Rehost Y, Replatform Z…" with the **one workload you debated longest**.

## Strategy cheat sheet (instructor reference; share with class if asked)

| R | Meaning | When | Tool |
|---|---|---|---|
| **Retire** | Stop running it | Nobody uses it; you're paying for hopium | n/a |
| **Retain** | Leave on-prem (for now) | License-locked, regulatory, latency, or sunset planned | n/a |
| **Rehost** | Lift-and-shift, same OS / app | Need to move now; refactor later | **MGN** for VMs; Storage Gateway / DataSync for data |
| **Relocate** | Same hypervisor, different host | VMware on-prem → VMware Cloud on AWS | VMware Cloud on AWS |
| **Repurchase** | Drop and replace with SaaS | Commodity workload (email, CRM, wiki) | Workspaces, M365, Salesforce, SaaS catalog |
| **Replatform** | Rehost with one optimization | Move a DB to RDS instead of EC2-on-which-the-DB-runs | RDS, ElastiCache, MSK, App Runner |
| **Refactor** | Rewrite to be cloud-native | Long horizon; enables business value (multi-tenancy, scale) | Lambda, EKS, Aurora Serverless, EventBridge |

## What good looks like (Portfolio A example answers — don't peek until you've drafted)

| # | Strategy | Target | Why |
|---|---|---|---|
| 1 Java 8 monolith | Rehost (then refactor later) | EC2 + MGN | Original devs gone — refactor risk too high day 1; rehost to buy time |
| 2 Oracle 11g | Replatform | RDS for Oracle (or AWS DMS to PostgreSQL) | Eliminates patching toil; Oracle license cost may force DMS |
| 3 Tomcat fleet | Replatform | ECS or Elastic Beanstalk | App is stateless; containers reduce Ops |
| 4 Lotus Notes | Repurchase | Microsoft 365 | Vendor sunset is the forcing function |
| 5 Wiki | Repurchase | Confluence Cloud | Commodity workload |
| 6 Cold backups | Replatform | S3 Glacier Deep Archive + DataSync | Storage tier match for access pattern |
| 7 .NET CRM | Refactor (long-term) / Rehost (now) | EC2 first; eventually break out modules to ECS / Lambda | Business logic value; hard to walk away from |
| 8 Crystal Reports | Retire | n/a | Generate the board pack from QuickSight off the existing data warehouse |

## Share-back format

Each pair gets 2 minutes. State the portfolio, your call mix ("we Retired 1, Rehosted 3, Replatformed 2, Repurchased 1, Refactored 1"), and walk through the **one workload you debated longest**. Include the deciding factor.

## Reflection

The most common mistake is **Refactoring everything**. It's expensive, takes years, and the business gets nothing in the meantime. The 7 Rs is a *portfolio* tool — you're balancing speed, risk, and cost across the entire estate. Most successful migrations are 60% Rehost + Replatform.
