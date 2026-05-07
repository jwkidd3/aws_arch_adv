# Lab 12 — Cost Explorer + Budgets

## Objective

Build a tag-grouped Cost Explorer report and a Budget that emails you when spend crosses a threshold. The Budget alarm is the part that actually runs in production — every account should have one.

## Time budget: 30 minutes

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. **Note:** Cost Explorer needs ~24 hours of data after first activation. If your Sandbox account is fresh, your Cost Explorer will be empty — the instructor will demo the report from the management account, and you'll focus on building the Budget alarm in your own Sandbox.
3. **If you see "You don't have access" on Cost Explorer**, your management account has restricted member-account billing access. Skip Parts A/C/E and do only Part D (Budgets) — Budgets create works regardless.

## Part A — Activate Cost Explorer (2 min)

- **Billing and Cost Management → Cost Explorer**
- If prompted, click **Launch Cost Explorer**. (Activation takes a few minutes; data starts populating immediately and historical data fills in over ~24 hours.)

## Part B — Activate cost allocation tags (3 min)

- **Billing and Cost Management → Cost allocation tags**
- Find `Owner` and `Course` in the user-defined tags list.
- Activate both. (User-defined tags must be activated before they show up in Cost Explorer reports.)
- Note: **tag activation only affects costs incurred after activation.** This is one of the most common AWS finance mistakes — activating tags after the fact and being surprised that historical data isn't grouped.

## Part C — Build a saved Cost Explorer report (5 min, instructor-led if Sandbox is fresh)

The instructor demos this from the management account where data exists; you follow along reading-only in your own account if data is missing.

- **Cost Explorer → Reports → Create new report**
- Date range: **Last 7 days**
- Granularity: **Daily**
- Group by → **Tag** → `Course`
- Filters: Tag `Course = archadv`
- Save report as `archadv-spend-by-course`.

The instructor's account should show a small bar chart with daily archadv spend. Your account will be empty (until tomorrow).

## Part D — Build a Budget with email alert (15 min)

This is the important part. Do this **in your own Sandbox account.**

### 1. Create the Budget

- **Billing and Cost Management → Budgets → Create a budget**
- **Budget setup: Customize (advanced)** → Next
- **Budget type: Cost budget** → Next
- Name: `archadv-<you>-budget`
- Period: **Monthly**, renewal type: **Recurring budget**
- Budgeted amount: **$5** (intentionally low so it triggers during class)
- Budget scope: cost types defaults
- Budget tags filter: `Course = archadv` (optional — if the tag is not yet activated as a cost allocation tag, leave unfiltered)

### 2. Configure alerts

- Add an alert at:
  - **80% of budgeted amount, ACTUAL cost** → email
  - **100% of budgeted amount, FORECASTED cost** → email
- Email recipient: your own email address.
- Save.

### 3. Confirm delivery

- **If you used a plain email recipient** (the lab's path): there is **no confirmation step**. Budget alerts deliver directly via the Budgets service — historic guidance about confirming a subscription only applies to SNS topic subscribers.
- **If you used an SNS topic instead**: check your inbox for **"AWS Notification - Subscription Confirmation"** and click the link. Without it, no emails arrive.

### 4. Force a quick alarm (optional, 5 min)

If you want to see the alarm fire today rather than waiting:

- Lower the budget to **$0.50** instead of $5.
- Within ~6 hours of class spend, the 80% alarm fires (most archadv spend in a Sandbox-N account during class is $1–3).
- Restore to $5 after the demo.

## Part E — Review high-cost services (3 min, discussion)

In Cost Explorer (or the instructor's demo account):

- **Group by → Service**, last 7 days
- Identify the top 3 services. For a typical archadv class day they will be:
  1. **NAT Gateway** (often the #1 surprise — $0.045/hr × N students × 9 hours)
  2. **EC2** (the bastion / ASG instances)
  3. **Storage Gateway m5.xlarge** (only on Module 4 day; expensive if left running)

Discussion: **the most effective cost optimization is destroying the resource**. Lab cleanups exist for a reason.

## Validation checklist

- [ ] Cost Explorer is activated
- [ ] `Owner` and `Course` cost allocation tags are activated
- [ ] Budget exists at $5/month with 80% actual + 100% forecasted alerts
- [ ] Email subscription confirmed (you clicked the link)
- [ ] You can name the top 3 cost contributors in your Sandbox

## Cleanup

Leave the Budget in place — it's the one thing in this lab you should keep. Everything else is just reporting.

## Stretch goals

- Create a **Savings Plan recommendation** report. (Cost Explorer → Recommendations → Compute Savings Plans). The recommendations need 7+ days of usage data; the instructor demos from the management account.
- **AWS Cost Anomaly Detection** is auto-enabled when Cost Explorer activates and ships with an AWS-services monitor. Inspect it. Then add a **customer-managed monitor** scoped to a tag value (e.g., `Course=archadv`) with an SNS action. This is the alarm you actually want long-term — Budgets fire on absolute thresholds; Anomaly Detection fires on *unusual patterns*.
- Read the AWS pricing for one of these and quote the per-hour cost: NAT Gateway, S3 Standard, an `m5.xlarge` EC2, KMS request, CloudFront request. Surprise yourself.
