# Lab 6 — Build & deploy a container on ECS Fargate

## Objective

Build a container image, push it to ECR, then run it as an **ECS Fargate** service behind an **Application Load Balancer**. End with a rolling update so you see ECS draining old tasks while bringing up new ones.

## Time budget: 50 minutes

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. You need a VPC with **public + private subnets across 2 AZs and a NAT** — reuse Lab 1's VPC. **Do not use the default VPC** — it has only public subnets, and Step 6 below requires private subnets with NAT for the Fargate tasks.
3. Open **CloudShell** in `us-east-1` (top-right toolbar). All build steps run here.

## Steps

### 1. Create the ECR repository (2 min)

- **Amazon ECR → Repositories → Create repository**
- Name: `archadv-<you>-hello`
- Image scanning: enable
- Encryption: AES-256
- Create.

Note the **URI** — looks like `123456789012.dkr.ecr.us-east-1.amazonaws.com/archadv-<you>-hello`.

### 2. Build the image (CloudShell, 5 min)

In CloudShell:

```bash
mkdir -p hello && cd hello

cat > Dockerfile <<'EOF'
FROM public.ecr.aws/docker/library/nginx:1.27-alpine
RUN echo '<h1>archadv hello v1</h1>' > /usr/share/nginx/html/index.html
EOF

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/archadv-<you>-hello

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com
docker build -t archadv-hello:v1 .
docker tag archadv-hello:v1 $REPO:v1
docker push $REPO:v1
```

Replace `<you>` with your name throughout. The push should complete in 30–60 sec.

### 3. ECS cluster (1 min)

- **Amazon ECS → Clusters → Create cluster**
- Name: `archadv-<you>-cluster`
- Infrastructure: **AWS Fargate (serverless)**
- Create. (Cluster is empty until you add a service.)

### 4. Task definition (3 min)

- **ECS → Task definitions → Create new task definition**
- Family: `archadv-<you>-hello`
- Launch type: Fargate
- OS, architecture: Linux/X86_64
- CPU: `0.25 vCPU`, Memory: `0.5 GB`
- Task role: leave blank
- Task execution role: **Create new** (will be created with `AmazonECSTaskExecutionRolePolicy`)
- Container:
  - Name: `web`
  - Image URI: `<account>.dkr.ecr.us-east-1.amazonaws.com/archadv-<you>-hello:v1`
  - Port: `80` (TCP)
- Create.

### 5. Application Load Balancer (5 min)

- **EC2 → Load Balancers → Create load balancer → Application**
- Name: `archadv-<you>-alb`
- Scheme: internet-facing
- VPC: yours (or default)
- Mappings: 2 AZs, **public** subnets in each
- Security group: new — allow `80/tcp` from `0.0.0.0/0`
- Listener: `HTTP:80`
- Target group: **Create target group** in a new tab:
  - Type: **IP addresses**
  - Name: `archadv-<you>-tg`
  - Protocol: HTTP, port `80`
  - VPC: same
  - Health check path: `/`
  - Create.
- Back in the ALB tab, refresh and select the new target group as the default action.
- Create the ALB. Wait ~2 min until state `Active`.

### 6. ECS service (3 min)

- **ECS → Clusters → archadv-<you>-cluster → Services → Create**
- Compute: Fargate, latest platform version
- Application type: Service
- Family: `archadv-<you>-hello`, latest revision
- Service name: `archadv-<you>-hello-svc`
- Desired tasks: `2`
- Networking: your VPC, **private** subnets, security group: create new — allow `80/tcp` from the **ALB's security group** only
- Public IP: **off** (Fargate tasks egress via NAT)
- Load balancing: Application Load Balancer
  - Choose `archadv-<you>-alb`, listener `80:HTTP`
  - Target group: `archadv-<you>-tg`
- Create. Wait ~3 min until **Last status: RUNNING** for both tasks.

### 7. Validate

```bash
ALB=$(aws elbv2 describe-load-balancers --names archadv-<you>-alb --query 'LoadBalancers[0].DNSName' --output text)
curl http://$ALB
# Expected: <h1>archadv hello v1</h1>
```

### 8. Rolling update (5 min)

In CloudShell:

```bash
sed -i 's/v1/v2/' Dockerfile
docker build -t archadv-hello:v2 .
docker tag archadv-hello:v2 $REPO:v2
docker push $REPO:v2
```

In the console:

- **ECS → Task definitions → archadv-<you>-hello → Create new revision**. Change the image tag from `:v1` to `:v2`. Create.
- **ECS → Services → archadv-<you>-hello-svc → Update**. Pick the new revision. Update.
- Watch the **Tasks** tab. ECS will start 2 new tasks, wait for them to be healthy, then drain the 2 old ones.

While the rollout is in progress, run this in a CloudShell loop:

```bash
while true; do curl -s http://$ALB; sleep 1; done
```

You'll see the response transition from `v1` to `v2` as old tasks drain. There should be **zero failed responses** during the rollout — that's the point.

## Validation checklist

- [ ] ECR repository contains `:v1` and `:v2` images
- [ ] ALB DNS returns the expected HTML on the public internet
- [ ] ECS service has 2 RUNNING tasks
- [ ] Rolling update completes with no failed `curl` responses
- [ ] After update, ALB returns `v2` payload
- [ ] Tasks have **no public IP**; they reach the internet only via NAT (or not at all)

## Cleanup

1. ECS service → Update → desired tasks `0`, then **Delete**.
2. ECS cluster → Delete.
3. ALB → Delete. Target group → Delete.
4. ECR repository → Delete (and image scan results).
5. Task execution role → Delete.

## Stretch goals

- Add **Container Insights** to the cluster and inspect a task's CPU and memory metrics during the rolling update.
- Switch the ALB listener to **HTTPS:443** with an ACM-issued certificate (you'll need a Route 53 hosted zone you control or DNS validation through email — instructor-provided).
- Add an **ECS service auto-scaling policy** (target tracking on CPU 50%) and trigger it with `ab` from CloudShell.
