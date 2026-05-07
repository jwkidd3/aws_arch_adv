output "tgw_id" {
  value = aws_ec2_transit_gateway.tgw.id
}

output "prod_ec2_id" {
  value = aws_instance.ec2["prod"].id
}

output "nonprod_ec2_id" {
  value = aws_instance.ec2["nonprod"].id
}

output "shared_ec2_id" {
  value = aws_instance.ec2["shared"].id
}

output "prod_ec2_private_ip" {
  value = aws_instance.ec2["prod"].private_ip
}

output "nonprod_ec2_private_ip" {
  value = aws_instance.ec2["nonprod"].private_ip
}

output "shared_ec2_private_ip" {
  value = aws_instance.ec2["shared"].private_ip
}

output "lab_bucket" {
  value = aws_s3_bucket.lab.bucket
}

output "s3_endpoint_id" {
  value = aws_vpc_endpoint.s3_prod.id
}
