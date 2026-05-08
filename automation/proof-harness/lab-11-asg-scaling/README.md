# Lab 11 proof harness

Builds: VPC + ALB + ASG (min=2, max=6, desired=2) + target tracking scaling policy on `ALBRequestCountPerTarget = 10`.

## What it asserts

- ALB is `active`
- ASG sized 2/2/6 (desired/min/max)
- Health check type is `ELB`
- 2/2 targets become `healthy` in the TG within 6 min
- ALB returns 200 on `/`
- Scaling policy type is `TargetTrackingScaling`
- **Predefined metric is `ALBRequestCountPerTarget`** (the lab's whole point — *this* metric, not CPU)
- Target value is `10`
- Auto-created CloudWatch alarms exist for the policy

## What it does NOT assert

- Actual load generation (~5 min `ab` run + 3 min wait for scale-up). The behavioral lesson — scale-up actually triggers — is for the instructor's pre-class dry-run, not weekly CI.
- Scale-back-down (15 min cooldown).
- Predictive scaling (stretch goal).

## Cost (approximate, per harness run)

- NAT Gateway: $0.045/hr
- ALB: $0.0225/hr base
- 2 EC2 t3.small: ~$0.04/hr
- CloudWatch alarms: $0.10/month — prorated, pennies

Per run (~10 min wall clock): **~$0.04**. Weekly CI: ~$2/year.
