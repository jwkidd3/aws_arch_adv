
# Lab: Hybrid Connectivity with AWS

## Objective
Establish secure hybrid connectivity between an on-premise simulation and AWS using:
- VPN over Internet
- AWS Transit Gateway

## Part A: Console Steps
1. Create a Customer Gateway
2. Create a Virtual Private Gateway
3. Attach the VGW to a VPC
4. Create a Site-to-Site VPN connection
5. Configure routing

## Part B: Terraform Steps
1. Define customer_gateway and vpn_connection resources
2. Attach VGW to VPC
3. Update route tables for VPC and simulated on-prem

## Validation
- Use ping/traceroute from EC2 to verify tunnel
- Check VPN connection status in console
