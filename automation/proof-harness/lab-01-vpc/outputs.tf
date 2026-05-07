output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "nat_gateway_ids" {
  value = module.vpc.natgw_ids
}

output "internet_gateway_id" {
  value = module.vpc.igw_id
}

output "workload_id" {
  value = aws_instance.workload.id
}

output "ami_id" {
  value       = data.aws_ami.al2023.id
  description = "Resolved Amazon Linux 2023 AMI — drift here means a new AMI was published or the old one was deprecated"
}
