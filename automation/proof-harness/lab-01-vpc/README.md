# Lab 1 proof harness

Builds: VPC `10.0.0.0/16` with 2 public + 2 private subnets across 2 AZs, IGW, single NAT, and a private-subnet workload EC2 reachable via SSM.

## What it asserts (matches the lab's validation checklist)

- VPC has `10.0.0.0/16` CIDR
- 2 public + 2 private subnets across 2 AZs
- Public route tables route `0.0.0.0/0 → igw-*`
- Private route tables route `0.0.0.0/0 → nat-*`
- Workload EC2 has **no public IP**
- Workload can reach the internet via the NAT (`curl https://checkip.amazonaws.com` returns 200)

## What it does NOT assert (vs. the student lab)

- SSH bastion connectivity from a laptop — CI uses SSM Session Manager instead. Same architectural assertion (private workload reachable via secure mechanism through the public path), different mechanism. Lab teaches SSH because students bring laptops; CI uses SSM because it's API-driven.
- Tag presence — left to CI policy / Sandbox SCPs.
- Well-Architected Tool review — not automatable.

## Run locally

```bash
cd automation/proof-harness/lab-01-vpc
terraform init
terraform apply -auto-approve
./validate.sh
terraform destroy -auto-approve
```

Or via orchestrator: `automation/tools/run-harness.sh lab-01-vpc`

## Cost (approximate, per harness run)

- 1 NAT Gateway: ~$0.045/hr
- 1 EIP: free while attached
- 1 EC2 `t3.micro`: ~$0.01/hr
- 4 subnets, 2 RTs: free

Per run (apply + validate + destroy ≈ 12 min): **< $0.05**. Weekly CI: ~$0.20/year for this lab.
