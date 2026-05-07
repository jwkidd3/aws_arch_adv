# Lab 11 — ASG with custom CloudWatch metric scaling

## Objective

Build an ALB + ASG that scales on **request-count-per-target** (not CPU). Generate load and watch the ASG add instances. The point is to internalize the durable lesson: **the scaling metric must be the leading indicator of saturation**, not a lagging one. A queue-driven workload that scales on CPU will never scale up; a request-driven workload that scales on request count will.

## Time budget: 30 minutes

This replaces the prior paper exercise. The design-thinking still happens — discussion at the end (5 min) walks through the same scenario cards (spiky news site, internal HR app, real-time game backend, batch image, IoT) and asks "would this trigger work for that workload? Why?".

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. You need a VPC with public + private subnets — reuse Lab 1's, or rebuild via the VPC wizard.
3. Open CloudShell (used for load generation in Step 5).

## Steps

### 1. Launch template (3 min)

- **EC2 → Launch templates → Create launch template**
- Name: `archadv-<you>-lab11-lt`
- AMI: Amazon Linux 2023
- Instance type: `t3.small` (`t3.micro` is unsupported in `us-east-1b`)
- Key pair: skip — we'll use SSM if needed
- Security group: create new — allow `80/tcp` from the soon-to-be-created ALB SG (we'll wire this in step 2)
- IAM instance profile: any role with `AmazonSSMManagedInstanceCore`
- User data:

```bash
#!/bin/bash
dnf install -y httpd
systemctl enable --now httpd
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
HOST=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
echo "<h1>archadv $HOST</h1>" > /var/www/html/index.html
```

- Create.

### 2. ALB + target group (5 min)

- **EC2 → Load Balancers → Create → Application**
- Name: `archadv-<you>-lab11-alb`
- Scheme: internet-facing
- VPC: yours; mappings: 2 public subnets across 2 AZs (avoid `us-east-1b`)
- Security group: new — `80/tcp` from `0.0.0.0/0`
- Listener: HTTP:80
- Target group: create new (instances type, port 80, health check `/`)
- Create. Wait until `Active`.

Now go back to the launch template's security group and allow `80/tcp` from the ALB SG.

### 3. Auto Scaling Group with custom-metric scaling (7 min)

- **EC2 → Auto Scaling Groups → Create**
- Name: `archadv-<you>-lab11-asg`
- Launch template: yours, latest version
- VPC: yours; subnets: 2 **private** subnets across 2 AZs (avoid `us-east-1b`)
- Attach to the load balancer's target group from step 2
- Health check type: **ELB**
- Group size: **min 2, desired 2, max 6**
- **Scaling policy: Target tracking scaling policy**
  - Metric type: **Application Load Balancer request count per target**
  - Target value: **`10`** (10 requests/min/instance — intentionally low so we can trigger it from CloudShell)
  - Target group: pick the one from step 2
  - Instance warmup: 60 sec
- Create. Wait ~3 min until 2 instances are `InService` in the target group.

### 4. Validate the baseline (2 min)

```bash
ALB=$(aws elbv2 describe-load-balancers --names archadv-<you>-lab11-alb --query 'LoadBalancers[0].DNSName' --output text)
for i in 1 2 3 4 5; do curl -s http://$ALB; done
```

You should see two instance IDs alternating — round-robin across the 2 ASG instances.

### 5. Generate load and watch the ASG scale up (10 min)

In CloudShell:

```bash
# Apache Bench is pre-installed on AL2023; CloudShell uses AL2023 too
sudo dnf install -y httpd-tools 2>/dev/null || true

# Send 10,000 requests with 50 concurrent connections
ab -n 10000 -c 50 http://$ALB/
```

While `ab` runs (~2-3 min), open another browser tab to **CloudWatch → Metrics → AWS/ApplicationELB → Per AppELB, per TG Metrics → RequestCountPerTarget**. You'll see it spike well above 10.

Then in the **EC2 → Auto Scaling Groups → archadv-<you>-lab11-asg → Activity** tab: a new scaling activity appears within ~1 min:

```
"Launching a new EC2 instance" — Cause: At <time>, a monitor alarm
TargetTracking-archadv-<you>-lab11-asg-AlarmHigh-... in state ALARM triggered
policy archadv-<you>-lab11-asg-target-tracking..., changing the desired
capacity from 2 to 3.
```

Refresh until you see the new instance go `InService` (~3 min total).

### 6. Watch it scale back down (5 min — optional, can skip)

After `ab` finishes, RequestCountPerTarget drops. Within 15 min, the ASG scales back down to 2. You may not have time to wait — note the behavior and move on.

## Validation checklist

- [ ] ASG has 2 instances `InService` initially
- [ ] Target tracking scaling policy on `ALBRequestCountPerTarget`, target value `10`
- [ ] Under load, ASG scaling activity shows "changing the desired capacity from 2 to 3" (or higher)
- [ ] CloudWatch metric `RequestCountPerTarget` exceeds 10 during load
- [ ] After load stops, ASG scales back to 2 (eventually)

## Discussion (5 min — instructor-led)

Hand out the scenario cards from the original Module 11 exercise. For each scenario, ask the room:

1. **Spiky news site (90% reads, 50× spikes)** — would `RequestCountPerTarget` work? *Yes — request count IS the saturation indicator.*
2. **Internal HR app (CPU-bound at peak, idle off-hours)** — would request count work? *Maybe, but **scheduled scaling** (`0 8 * * MON-FRI` up, `0 18 * * MON-FRI` down) is cheaper and simpler.*
3. **Real-time game backend (10K concurrent connections)** — request count? *No — connections, not requests, are the bottleneck. Need a custom metric for active connections.*
4. **Batch image processing (queue-driven)** — request count? *No — there's no ALB. The right metric is **SQS queue depth** (or `ApproximateNumberOfMessagesVisible`).*
5. **IoT telemetry ingestion (1M events/sec)** — request count? *No — for Kinesis, use `IncomingRecords` or `IncomingBytes`. For Lambda fronting Kinesis, **iterator age**.*

The durable lesson: scale on the metric that **leads** saturation, not the one that **lags** it. CPU is the lagging indicator for memory-bound or queue-bound workloads.

## Cleanup

1. ASG → Update → desired/min = 0, then **Delete**.
2. ALB → Delete; target group → Delete.
3. Launch template → Delete.
4. Security groups → Delete.

## Stretch goals

- Add a **second** scaling policy: target tracking on average CPU 50%. With nginx serving static content, CPU stays low even under load — show that the CPU policy doesn't fire while the request-count policy does.
- Add a **predictive scaling** policy. AWS analyzes 14 days of metric data to forecast and pre-scale. Not useful in a 30-min lab, but the configuration is illustrative.
- Set up the same workload on **EC2 + Lambda** in parallel and compare the cost of the same load served by ASG vs Lambda.
