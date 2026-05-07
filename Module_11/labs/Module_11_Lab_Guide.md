# Exercise 11 — Paired scaling design (no console)

## Objective

Design — on paper or whiteboard — the **scaling triggers and traffic-routing strategy** for a real-shape workload. The point is to internalize the decision lens, not to deploy.

## Time budget: 20 minutes

- 12 min — pair work
- 8 min — share-back to the room

## Setup

Pair up with the person next to you. The instructor hands each pair a **scenario card**. Sample scenarios:

> **Scenario A — Spiky news site.** Traffic is 100 req/sec baseline, but spikes 50× to 5,000 req/sec within 60 sec when a story goes viral. 90% reads, 10% writes. Globally distributed audience.

> **Scenario B — Internal HR app.** 200 employees, business hours only. CPU-bound at peak (~70%); idle outside business hours. Single region.

> **Scenario C — Real-time game backend.** 10,000 concurrent connections per region; tail-latency-sensitive. Players in NA, EU, APAC.

> **Scenario D — Batch image processing.** Long-running CPU work; queue-driven. Tolerant of latency, intolerant of cost.

> **Scenario E — IoT telemetry ingestion.** 1M events/sec sustained, with a 10× burst at top-of-hour. Writes only.

## Deliverable (whiteboard or shared doc)

For your scenario, sketch and label:

1. **Compute tier** — EC2 ASG, ECS, Fargate, Lambda, App Runner, or something else? Why?
2. **Scaling trigger** — pick **one primary metric** and justify:
   - CPU utilization (target tracking)
   - Memory utilization
   - Custom CloudWatch metric (specify which)
   - Request count per target (ALB target metric)
   - SQS queue depth
   - Schedule-based
3. **Min / max / desired** — what numbers, and what's the reasoning behind the floor and ceiling?
4. **Traffic routing** — Route 53 policy (simple, latency, geo, weighted, failover) or CloudFront. Why?
5. **The thing you'd cut first** if cost pressure forced a 30% reduction.

## Share-back format

Each pair gets 1 minute. Briefly state the scenario, then your design, then the **one design decision you debated most**. The room votes 👍/👎 on that decision.

## What good looks like

Spike-tolerant traffic (Scenario A) → Lambda or Fargate with high concurrency, request-count-based scaling, **CloudFront** in front, multi-region with latency routing.

Bursty queue-driven (Scenarios D, E) → ECS or Lambda triggered by queue depth (SQS) or shard-iterator-age (Kinesis).

Predictable schedule (Scenario B) → scheduled scaling (`0 8 * * MON-FRI` up, `0 18 * * MON-FRI` down) — it's the cheapest, simplest, and still nobody uses it.

Tail-latency game (Scenario C) → request-count-per-target plus low health-check thresholds; multi-region with geoproximity routing and **fallback** to nearest active region.

## What "wrong" looks like

- "Scale on CPU" for a queue-driven workload (CPU stays low while the queue grows; you never scale up)
- "Multi-region active-active" without considering data consistency
- No cost discussion at all

## Reflection (instructor)

Bring it home: the durable lesson isn't the specific trigger — it's that **the scaling metric must be the leading indicator of saturation**, not the lagging indicator. CPU is the lagging indicator for a memory-bound or queue-bound workload.
