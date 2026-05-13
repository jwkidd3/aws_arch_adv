# Lab 3 — Site-to-Site VPN + Route 53 Resolver (configure-only)

## Objective

Build all the AWS-side resources for a hybrid network: Customer Gateway, Virtual Private Gateway, Site-to-Site VPN connection, route propagation, and a Route 53 Resolver outbound endpoint with a forwarding rule. **The on-prem side is intentionally absent** — there is no IPsec responder for the tunnel to negotiate with, so the tunnel will stay `DOWN`. That's the teaching point: you'll see exactly what AWS provides to a hybrid customer, what the on-prem network engineer would need to plug in on their side, and what state AWS reports while the other side is silent.

## Time budget: 50 minutes

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. You should have a VPC `10.0.0.0/16` from Lab 1. (The bastion EC2 isn't needed for this lab.)
3. Use these **placeholder "on-prem" values** for your CGW and VPN config:

| Value | Use this |
|---|---|
| On-prem peer public IP | `203.0.113.10` (RFC 5737 documentation range — unroutable on purpose) |
| Pre-shared key | `archadv-lab3-2026` |
| On-prem BGP ASN | `65000` |
| On-prem private CIDR | `10.99.0.0/16` |
| On-prem DNS resolver IP | `10.99.10.10` |
| On-prem DNS zone | `corp.example.com` |

AWS accepts these values at configuration time — it doesn't check whether the peer actually exists until it tries to negotiate.

## Steps

### 1. Customer Gateway (2 min)

- **VPC → Customer gateways → Create customer gateway**
- Name: `archadv-<your-name>-cgw`
- BGP ASN: `65000`
- IP address: `203.0.113.10`
- Create.

### 2. Virtual Private Gateway (2 min)

- **VPC → Virtual private gateways → Create virtual private gateway**
- Name: `archadv-<your-name>-vgw`
- ASN: **Amazon default ASN**
- Create.
- Select it → **Actions → Attach to VPC** → choose your VPC.

### 3. Site-to-Site VPN connection (5 min)

- **VPC → Site-to-Site VPN connections → Create VPN connection**
- Name: `archadv-<your-name>-vpn`
- Target gateway type: **Virtual Private Gateway**, choose `archadv-<your-name>-vgw`
- Customer Gateway: **Existing**, choose `archadv-<your-name>-cgw`
- Routing options: **Dynamic (BGP)**
- Pre-shared key storage type: **Standard**
- Outside IP address type: **PublicIpv4**
- Tunnel options: leave **inside CIDRs** at AWS default. Expand **Tunnel options** for each tunnel and set **pre-shared key** to `archadv-lab3-2026`.
- Create.

### 4. Enable route propagation (2 min)

- **VPC → Route Tables** → select your VPC's private subnet route table
- **Route propagation tab** → Edit → enable propagation from the VGW.

This *would* cause BGP-learned routes (e.g., `10.99.0.0/16`) to appear here once the tunnel was UP. Since the on-prem side is absent in this lab, the propagation is configured but inert.

### 5. Observe the AWS-side state (5 min)

- **VPC → Site-to-Site VPN connections** → select yours → **Tunnel details** tab.
- Both tunnels will be in `DOWN` state with "Last status change: ... Status: DOWN" and a status message like *"IPSEC IS DOWN"* or *"No response from peer"*. That's expected — there's no responder at `203.0.113.10`.
- Click **Download configuration**. Pick a vendor (e.g., Cisco ASA, Cisco IOS, generic OpenVPN-style). The downloaded file is the **exact config a real on-prem network engineer would paste into their router**. Review it — note the IPsec proposals (encryption algorithms, DH groups), the inside tunnel IPs (e.g., `169.254.21.0/30`), the AWS-side public IP and BGP ASN, and the PSK.
- This downloaded file is the *complete contract* AWS offers for hybrid connectivity. Everything between this and a working tunnel is on the on-prem side.

### 6. Route 53 Resolver outbound endpoint (10 min)

The Resolver pieces don't depend on the tunnel being UP — they're independent DNS infrastructure inside your VPC. Build them anyway because they're the second half of every real hybrid-DNS design.

- **Route 53 → Resolver → Outbound endpoints → Create**
- Name: `archadv-<your-name>-r53out`
- VPC: your VPC
- Security group: create new — allow UDP/TCP `53` outbound to `10.99.0.0/16`
- IP addresses: 2 IPs across 2 AZs (use the private subnets from Lab 1)
- Create. Wait ~3 min until status `Operational`.

### 7. Forwarding rule (2 min)

- **Route 53 → Resolver → Rules → Create**
- Rule type: **Forward**
- Domain name: `corp.example.com`
- VPCs that use this rule: your VPC
- Outbound endpoint: the one from step 6
- Target IP: `10.99.10.10` on port `53`
- Create.

### 8. Discussion — what's missing? (5 min, instructor-led)

Hand the room these questions:

1. What would `dig host.corp.example.com` return right now if you ran it from inside your VPC?
2. Look at the Resolver outbound endpoint's logs (CloudWatch). When would queries actually go out the endpoint, and what would happen to them if they did?
3. The downloaded VPN config in Step 5 has all the IPsec/BGP parameters. What does the on-prem engineer need to physically do with their router for the tunnel to come up?
4. If you had Direct Connect instead of Site-to-Site VPN, which parts of this lab would change? (Hint: very few — that's the point.)

## Validation checklist

- [ ] CGW exists with on-prem peer IP `203.0.113.10`, ASN `65000`
- [ ] VGW exists and is attached to your VPC
- [ ] Site-to-Site VPN exists; both tunnels show `DOWN` with a "No response from peer" or equivalent status message
- [ ] Tunnel details show inside IPs (169.254.x.x/30) and your VPN's AWS-side public IPs
- [ ] You downloaded the vendor-specific configuration file and reviewed the IPsec proposals
- [ ] Private route table has route propagation enabled (propagated routes section is empty — expected)
- [ ] Route 53 Resolver outbound endpoint is `Operational`
- [ ] Forwarding rule for `corp.example.com` exists and is associated with your VPC

## Cleanup

In this order to avoid dependency errors:

1. Delete the Resolver forwarding rule.
2. Delete the Resolver outbound endpoint.
3. Delete the Site-to-Site VPN connection.
4. Detach the VGW from the VPC, then delete the VGW.
5. Delete the Customer Gateway.
6. **Leave the VPC** — it's reused by Labs 4, 6, 8, 11, 13, and 14. Lab 1's cleanup section is the right place to delete it (at end of course).

## Stretch goals

- Open the **AWS VPN troubleshooting guide** for your downloaded vendor config and find the `crypto isakmp policy` (or equivalent IKE parameters) line. Identify which encryption algorithm AWS proposed.
- Inspect the **CloudWatch metrics** for your VPN connection — `TunnelState`, `TunnelDataIn`, `TunnelDataOut`. Confirm `TunnelState` is 0 (DOWN) on both tunnels.
- Read the **Direct Connect vs Site-to-Site VPN** doc and write down which step in this lab would change if you swapped to DX. (Almost none — that's the point.)
