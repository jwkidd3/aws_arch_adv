# Lab 3 — Site-to-Site VPN + Route 53 Resolver

## Objective

Connect your Sandbox VPC to a simulated on-prem site over Site-to-Site VPN. Then use **Route 53 Resolver outbound endpoint** so EC2s in your VPC can resolve on-prem DNS records as if they were native AWS records. This is the "hybrid network" pattern most enterprises run.

## Time budget: 75 minutes (was 65 — VPN/BGP timing is hard to compress)

## Pre-flight

1. Sign in to `Sandbox<N>` via the access portal.
2. Region: `us-east-1`.
3. From your credentials packet, note these **on-prem simulator** values (provided by the instructor):
   - Public IP of the on-prem peer: `<SIM_PIP>`
   - Pre-shared key: `<SIM_PSK>`
   - On-prem BGP ASN: `65000`
   - On-prem private CIDR: `10.99.0.0/16`
   - On-prem DNS resolver IP: `<SIM_DNS_IP>` (inside `10.99.0.0/16`)
   - On-prem DNS zone: `corp.example.com`

You should already have a VPC `10.0.0.0/16` from Lab 1, with the bastion EC2 still running. If you destroyed either, recreate before proceeding.

**Bastion SG amendment (required):** Lab 1's bastion SG only allows SSH/22 from My IP. For Lab 3 you also need:

- **All ICMP - IPv4** from `10.99.0.0/16` (so `ping` to on-prem hosts works)
- **UDP 53** from `10.0.0.0/16` (so `dig` against the Resolver endpoint works)

Add both inbound rules to the bastion SG before starting.

## Steps

### 1. Customer Gateway (2 min)

- **VPC → Customer Gateways → Create**
- Name: `archadv-<your-name>-cgw`
- BGP ASN: `65000`
- IP address: `<SIM_PIP>`
- Create.

### 2. Virtual Private Gateway (2 min)

- **VPC → Virtual Private Gateways → Create**
- Name: `archadv-<your-name>-vgw`
- ASN: `Amazon default ASN`
- Create.
- Select it → **Actions → Attach to VPC** → choose your VPC.

### 3. Site-to-Site VPN connection (5 min)

- **VPC → Site-to-Site VPN connections → Create**
- Name: `archadv-<your-name>-vpn`
- Target gateway type: **Virtual Private Gateway**, choose `archadv-<your-name>-vgw`
- Customer Gateway: **Existing**, choose `archadv-<your-name>-cgw`
- Routing options: **Dynamic (BGP)**
- Tunnel 1 / Tunnel 2 — leave **inside CIDRs** to AWS default; set **pre-shared key** to `<SIM_PSK>` for both
- Create.

### 4. Enable route propagation (2 min)

- **VPC → Route Tables** → select the **private** subnet route table
- **Route propagation tab** → Edit → enable propagation from the VGW

This causes BGP-learned routes from the on-prem simulator (e.g., `10.99.0.0/16`) to appear automatically in your route table once the tunnel is up.

### 5. Wait for the tunnel (5–10 min)

- **VPC → Site-to-Site VPN connections** → select yours → **Tunnel details** tab.
- For a tunnel to come `UP`, the on-prem simulator must have an actively-peering IPsec daemon (the instructor confirms this in pre-class setup). If both tunnels stay `DOWN` after 15 min, escalate to the instructor — the simulator is not responding.
- One of the two tunnels typically moves to `UP` within 5–10 min once IKE handshakes complete. The other usually stays `DOWN` until traffic flows; that's expected (active/standby).
- While waiting, scroll back through the slide deck and note where on the diagram you are.

### 6. Route 53 Resolver outbound endpoint (10 min)

- **Route 53 → Resolver → Outbound endpoints → Create**
- Name: `archadv-<your-name>-r53out`
- VPC: your VPC
- Security group: create new, allow UDP/TCP `53` outbound to `10.99.0.0/16`
- IP addresses: 2 IPs across 2 AZs (use the private subnets from Lab 1)
- Create. Wait ~3 min until status `Operational`.

### 7. Forwarding rule (2 min)

- **Route 53 → Resolver → Rules → Create**
- Rule type: **Forward**
- Domain name: `corp.example.com`
- VPCs that use this rule: your VPC
- Outbound endpoint: the one from step 6
- Target IP: `<SIM_DNS_IP>` on port 53
- Create.

### 8. Test from inside the VPC (5 min)

CloudShell runs outside your VPC by default — for this test, you need to be *inside* your VPC.

Easiest: **SSH into the bastion EC2 from Lab 1**, then test. (Wait ~2 min after the tunnel goes `UP` for BGP route propagation to settle before running `dig`.)

```bash
# DNS resolution of the on-prem record
dig +short host.corp.example.com
# Expected: an IP from the 10.99.0.0/16 range

# Connectivity to that on-prem host
ping -c 3 <returned-ip>
```

This is the "aha" — your bastion just resolved a DNS record that lives in a separate datacenter, then routed traffic to it through the VPN tunnel, with no client-side configuration.

## Validation checklist

- [ ] CGW and VGW exist; VGW is attached to your VPC
- [ ] Site-to-Site VPN shows at least one tunnel `UP`
- [ ] Private route table shows propagated routes for `10.99.0.0/16`
- [ ] Route 53 Resolver outbound endpoint is `Operational`
- [ ] Forwarding rule for `corp.example.com` exists and is associated with your VPC
- [ ] `dig host.corp.example.com` from inside your VPC returns a `10.99.x.x` IP
- [ ] `ping` to that IP succeeds (assuming on-prem-simulator security group allows ICMP)

## Cleanup

In this order to avoid dependency errors:

1. Delete the Resolver forwarding rule.
2. Delete the Resolver outbound endpoint.
3. Delete the Site-to-Site VPN connection.
4. Detach the VGW from the VPC, then delete the VGW.
5. Delete the Customer Gateway.
6. **Leave the VPC** — it's reused by Labs 4, 6, 8, 11, 13, and 14. Lab 1's cleanup section is the right place to delete it (at end of course).

## Stretch goals

- Create a **Route 53 Resolver inbound endpoint** so the on-prem simulator can resolve a private hosted zone you create in your VPC — bidirectional DNS is the production pattern.
- Read the **Direct Connect** docs and write down which step in this lab would change if you swapped Site-to-Site VPN for a DX VIF. (Almost none of the AWS-side steps change — that's the point.)
