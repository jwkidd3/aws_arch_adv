# Lab 12 proof harness

Builds: a Cost Budget with a $5 monthly limit, 80% Actual alert + 100% Forecasted alert, both with email subscribers.

## What it asserts

- Budget exists with `$5 USD MONTHLY COST`
- Two notifications attached:
  - 80% ACTUAL with email subscriber
  - 100% FORECASTED with email subscriber
- Subscribers are configured for both

## What it does NOT assert

- Cost Explorer activation (account-level, ~24h delay before data populates — out of scope for an ephemeral harness)
- Cost allocation tag activation (also account-level + days-long propagation)
- Email delivery confirmation (would require a real inbox)
- AWS Cost Anomaly Detection auto-creation (recently introduced — could be added)

## Cost (approximate, per harness run)

- Budgets resource: free (AWS gives 2 budgets/account at no charge)
- IAM: free

Per run: **$0**. Weekly CI: **$0**.

## Note on test email

The default `noreply+lab12@example.com` is non-routable. AWS Budgets accepts the address at creation time but the alert email never delivers — that's fine for the harness. Override with `-var alert_email=...` if you want real delivery for a manual test.
