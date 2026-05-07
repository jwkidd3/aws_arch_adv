# Module 14 — Capstone: design and build a 3-tier web app

## Objective

Synthesize the course. Each pair receives a brief, sketches an architecture, then console-builds the highest-priority pieces in their Sandbox account. End with a short walkthrough explaining design decisions.

The point is **the design conversation**, not getting a fully-deployed multi-tier app online. Acceptance bar is realistic — see below.

## Time budget: 75 minutes total

- **25 min** — framing, recap, scenario brief, Q&A
- **15 min** — paired diagram
- **25 min** — paired console build (whichever pieces you prioritized)
- **10 min** — pair walkthroughs (5 min × 2 pairs picked by the instructor)

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. Pair up with the person next to you (or solo if odd).
3. Have a diagram tool ready: whiteboard, draw.io, Excalidraw, Lucidchart — anything that lets you sketch boxes and lines.

## Scenario brief

> **WidgetCo** sells configurable industrial widgets through a public web store and a private partner portal. Both are read-heavy with bursty write spikes around new product launches. Target: 99.95% availability. Data is partner-PII (think: contact info, contract terms — not financial or health).
>
> Today they run two ASP.NET apps on a fleet of 12 EC2s, one shared MySQL on EC2, and an S3 bucket for product images. They're growing 30% YoY.

## Required components in your design

Your architecture diagram must include:

1. **Network** — VPC layout (public / private subnets, AZ count, routing)
2. **Edge / WAF** — CloudFront + WAF + Shield Standard
3. **Web tier** — ALB + ASG (or Fargate)
4. **App tier** — separated from web tier (security and scaling)
5. **Database tier** — Aurora MySQL (in design: multi-AZ with reader endpoint for read-heavy. In the build slice below, single-writer is fine — multi-AZ creation alone takes ~15 min and won't fit in the 25-min budget.)
6. **Object storage** — S3 for product images, with CloudFront origin access control
7. **Secrets** — Secrets Manager + KMS CMK
8. **Observability** — CloudWatch dashboards, alarms, log groups
9. **CI/CD** — sketched, not built (CodePipeline + CodeDeploy or GitHub Actions)
10. **Cost guardrails** — Budget alarm; tagging strategy

## Build priorities (build what fits in 25 min)

Pick **2–3** of these to actually build in console; sketch the rest:

| Priority | Component | Console time |
|---|---|---|
| **High** | VPC (multi-AZ) | 5 min — VPC wizard |
| **High** | ALB + ASG with 2 instances | 10 min — Lab 8 pattern |
| **Medium** | Aurora MySQL cluster (single writer; kick off and move on — it will still be provisioning when 25 min ends, that's fine) | 10 min to *initiate*; full create ~15 min |
| **Medium** | S3 bucket + CloudFront distribution | 10 min |
| **Low** | WAF web ACL on the ALB | 5 min — Lab 8 pattern |
| **Optional** | Secrets Manager secret + KMS key | 5 min — Lab 9 pattern |

A sensible 25-minute slice: **VPC + ALB+ASG + Aurora**. Or: **VPC + S3+CloudFront + WAF**. Pick the slice that exercises the parts of the course you most want to lock in.

## Decisions you must justify in your walkthrough

1. **Why AZ count = 2 vs 3?** (cost vs availability)
2. **Why Aurora vs RDS MySQL?** (read replicas, recovery, cost)
3. **Why CloudFront in front of the ALB?** (latency, DDoS, cost)
4. **Where does Secrets Manager hold what?**
5. **What's the one thing you'd cut first under cost pressure?**

## Optional: Terraform reference

A reference Terraform starter exists at `Module_14/terraform/` for students who took the dedicated Terraform course and want to see the equivalent IaC. **It is optional.** The capstone is not graded on whether you used it.

## Walkthrough format

Two pairs are picked at random. Each gets 5 min:

- 1 min — your scenario interpretation
- 2 min — diagram tour
- 1 min — what you actually built
- 1 min — the decision you debated longest

The room offers one constructive question per walkthrough.

## Acceptance bar (any **one** counts as success)

- Working diagram covering the required components above
- Console-built proof-of-concept covering at least 2 tiers
- Walkthrough explains *why* each component was chosen, with one trade-off identified

You do not need a fully-running multi-tier app. The capstone is a **design exercise** with hands-on reinforcement.

## Cleanup

Tear down whatever you built — leaving an Aurora cluster running overnight is a quick way to spend $50 of someone else's money:

1. Delete Aurora cluster (writer first, then cluster).
2. Delete CloudFront distribution (disable first; takes ~15 min to fully delete — that's fine).
3. ALB → ASG → Launch template.
4. WAF web ACL.
5. S3 bucket (empty first).
6. KMS key (schedule deletion, 7-day waiting period).
7. VPC.

Leave the Budget alarm from Lab 12.

## Course close

One sentence per student to the room: *the one architecture decision you're changing on Monday.*

That's the course. Thanks for the time.
