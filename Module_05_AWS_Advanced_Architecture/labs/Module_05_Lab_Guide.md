
# Lab: Connecting AWS VPCs using Transit Gateway

## Objective
Connect two VPCs using AWS Transit Gateway and route traffic between them.

## Part A: Console Steps
1. Create two VPCs (VPC-A and VPC-B)
2. Create a Transit Gateway
3. Attach both VPCs to the TGW
4. Update route tables for both VPCs
5. Launch EC2 in each VPC and test communication

## Part B: Terraform Steps
1. Define aws_ec2_transit_gateway
2. Attach VPCs using aws_ec2_transit_gateway_vpc_attachment
3. Configure routing

## Validation
- SSH from one EC2 instance to another
- Check route tables and TGW propagation
