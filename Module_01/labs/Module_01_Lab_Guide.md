# Lab 1 — Well-Architected VPC (console build)

## Objective

Build a multi-AZ VPC by hand in the AWS console and validate it against the Well-Architected reliability and security pillars. The point is **building the network foundation every other lab will sit on**, while practicing the WAFR lens.

## Time budget: 50 minutes

## Pre-flight

1. Open the AWS access portal URL from your credentials packet.
2. Sign in with your IAM Identity Center user.
3. Choose your assigned account — `Sandbox<N>` — and the `AWSAdministratorAccess` role.
4. Click **Open AWS console**. Confirm the badge in the top-right reads `AWSAdministratorAccess @ Sandbox<N>`.
5. Set region to **US East (N. Virginia) — `us-east-1`** in the top-right region selector.

## Steps

### 1. Create the VPC

- Console: **VPC → Your VPCs → Create VPC**
- Resources to create: **VPC and more** (use the VPC wizard)
- Name tag auto-generation: `archadv-<your-name>`
- IPv4 CIDR: `10.0.0.0/16`
- Number of Availability Zones: **2**
- Number of public subnets: **2**, private subnets: **2**
- NAT gateways: **In 1 AZ** (cost-aware)
- VPC endpoints: **None** (we'll add S3 in Lab 5)
- DNS options: enable both **DNS hostnames** and **DNS resolution**
- Click **Create VPC**. Wait ~60 sec for the workflow to finish.

### 2. Tag everything

In the VPC, subnets, IGW, NAT, and route tables, add tags:
- `Owner=<your-name>`
- `Course=archadv`

### 3. Launch a public-subnet EC2 (the bastion)

- **EC2 → Launch instance**
- Name: `archadv-<your-name>-bastion`
- AMI: latest **Amazon Linux 2023**
- Instance type: `t3.micro`
- Key pair: create a new one named `archadv-<your-name>` (download the .pem)
- Network: your new VPC
- Subnet: one of the **public** subnets
- Auto-assign public IP: **Enable**
- Security group: create new — allow SSH (22) from **My IP**
- Launch.

### 4. Launch a private-subnet EC2 (the workload)

- Same flow as above. Name: `archadv-<your-name>-workload`.
- Subnet: one of the **private** subnets.
- Auto-assign public IP: **Disable**.
- Security group: new — allow SSH (22) from the **bastion's security group ID** (not from `0.0.0.0/0`).
- Launch.

### 5. Validate connectivity

From your laptop:

```bash
chmod 400 archadv-<your-name>.pem
ssh -i archadv-<your-name>.pem ec2-user@<bastion-public-ip>
```

From inside the bastion, SSH to the workload's private IP:

```bash
ssh -i archadv-<your-name>.pem ec2-user@<workload-private-ip>
```

From the workload, confirm internet egress works through the NAT:

```bash
curl -s https://checkip.amazonaws.com
```

You should see the **NAT Gateway's** public IP, not the workload's private IP.

## Validation checklist

- [ ] VPC exists with `10.0.0.0/16` and 2 public + 2 private subnets across 2 AZs
- [ ] Public subnets have a route `0.0.0.0/0 → igw-...`
- [ ] Private subnets have a route `0.0.0.0/0 → nat-...`
- [ ] Bastion is reachable from your laptop on port 22
- [ ] Workload is reachable **only via the bastion** (not from the public internet)
- [ ] Workload can `curl` an HTTPS URL through the NAT
- [ ] Every resource is tagged `Owner` + `Course=archadv`

## WAFR self-review

In **AWS Well-Architected Tool**, define a workload for this VPC and run the framework review. Capture three high-risk issues in the **Security** and **Reliability** pillars and discuss with your pair what you'd change before this VPC went to production.

## Cleanup

> **Important:** **Labs 3, 4, 6, 8, 11, 13, and 14 all reuse this VPC.** Do **not** delete it now if you're continuing the course. Defer cleanup until **end of class** (after Module 14 / capstone).
>
> If you must stop overnight between class days, the NAT Gateway costs ~$0.045/hr while running. Either accept ~$1/night per student or run cleanup at end-of-day and rebuild the VPC at the start of the next session (~5 min).

When you're ready to clean up (end of course, or end of day-1 if not continuing):

- Terminate both EC2s.
- **VPC → Your VPCs → select → Actions → Delete VPC** — this removes the subnets, route tables, IGW, and NAT in one shot.
- If Delete VPC errors on a NAT/EIP dependency, delete the NAT Gateway from **VPC → NAT gateways** first (wait ~1 min), then retry Delete VPC.
- **Release the Elastic IP** allocated for the NAT — **EC2 → Elastic IPs → Release**. NAT-allocated EIPs persist after VPC deletion and incur charges.
- Delete the key pair.

## Stretch goals

- Add a **VPC flow log** to the VPC, sending to a new CloudWatch log group. Generate traffic and inspect a few flow records.
- Replace the SSH bastion with **EC2 Instance Connect** or **Session Manager** — SSM is the production answer; bastions are legacy.
