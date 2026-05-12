# Lab 1 — Identity Center user + Well-Architected VPC

## Objective

Two parts. First (Part A): create your own IAM Identity Center user in the management account and grant it `AdministratorAccess` to your assigned Sandbox. This is your identity for the rest of the course. Second (Part B): build a multi-AZ VPC and validate it against the Well-Architected reliability and security pillars — the network foundation every other lab will sit on.

## Time budget: 60 minutes (10 min Part A + 50 min Part B)

## Pre-flight

You should have received from the instructor:

- A **starter credential** (username + password or sign-in link) that gets you into the **management account** `001613358280`. You'll use this once, in Part A.
- The **AWS access portal URL** for the org (looks like `d-xxxxxxxxxx.awsapps.com/start`). You'll use this after Part A as your normal sign-in.
- Your **assigned Sandbox account name** (e.g., `Sandbox7`) and account ID.

## Part A — Create your Identity Center user (10 min)

### 1. Sign into the management account

- Open the AWS console and sign in with the **starter credentials** from the instructor.
- Confirm the badge in the top-right shows account `001613358280` (the management account).
- Set region to **US East (N. Virginia) — `us-east-1`**.

### 2. Open IAM Identity Center

- Service search → **IAM Identity Center**.
- If asked, the org's IdC region is the same as your console session region.

### 3. Create your user

- Left sidebar → **Users** → **Add user**.
- Username: `<your-name>` (lowercase, no spaces — e.g., `alice` or `alice.smith`)
- Email: your real email (Identity Center will send an activation email here)
- First name / Last name: your own
- Password: **Generate a one-time password and share it with the user manually** (you'll receive the password on screen)
- Skip group assignment (we'll grant the permission set directly in step 4).
- Add user.

### 4. Assign yourself `AdministratorAccess` to your Sandbox

- **IAM Identity Center → AWS accounts** (left sidebar).
- Find your assigned `Sandbox<N>` in the account list and click into it.
- **Assign users or groups** → select your newly-created user from the **Users** tab → **Next**.
- **Permission sets**: select **`AdministratorAccess`** (an existing pre-staged permission set) → **Next**.
- **Submit**. Wait ~30 sec for the assignment to provision.

### 5. Sign out and sign back in as your new user

- Sign out of the starter session.
- Open the **AWS access portal URL** from your credentials packet (`d-xxxxxxxxxx.awsapps.com/start`).
- Sign in with the username + one-time password from step 3. You'll be prompted to set a new password and configure MFA.
- After sign-in, you should see exactly one account: `Sandbox<N>`. Click it → `AdministratorAccess` → **Open AWS console**.
- Confirm the badge in the top-right reads `AdministratorAccess @ Sandbox<N>`. **You are now in your own Sandbox.** You will not need the management account starter credentials again.

## Part B — Well-Architected VPC (50 min)

You're now signed in to your Sandbox as your own IdC user. Set region to **us-east-1**.

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

> **Important: do NOT delete the VPC.** It's reused by Labs 3, 4, 6, 8, 11, 13, and 14 across all 3 days of the course. The instructor will clean up VPCs centrally after the course ends.

Lab-1-specific cleanup:

- Terminate the **bastion** and **workload** EC2s — they're not needed for any other lab.
- Delete the key pair you created for the bastion.

Leave everything else (VPC, subnets, IGW, NAT, route tables, Elastic IP) in place.

## Stretch goals

- Add a **VPC flow log** to the VPC, sending to a new CloudWatch log group. Generate traffic and inspect a few flow records.
- Replace the SSH bastion with **EC2 Instance Connect** or **Session Manager** — SSM is the production answer; bastions are legacy.
