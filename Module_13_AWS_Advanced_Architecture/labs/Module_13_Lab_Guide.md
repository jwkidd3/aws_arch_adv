
# Lab: Migrating a Sample Workload to AWS

## Objective
Use AWS MGN (for EC2) and DMS (for DB) to simulate a lift-and-shift migration.

## Part A: Console Steps
1. Set up AWS MGN for VM migration
2. Launch replication agent on source VM
3. Test cutover process
4. Set up DMS to migrate an on-prem DB to RDS
5. Monitor migration progress

## Part B: Terraform Steps
1. Define RDS target DB (PostgreSQL or MySQL)
2. Create IAM roles for DMS
3. Define replication instance and endpoints (manual or reference)

## Validation
- Test app in new EC2 post-migration
- Validate data replication with query checks
