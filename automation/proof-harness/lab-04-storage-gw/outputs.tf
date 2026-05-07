output "storage_gateway_ami" {
  value       = data.aws_ami.storage_gateway.id
  description = "Resolved Storage Gateway AMI — drift here means AWS published a new gateway AMI or deprecated the old one"
}

output "datasync_ami" {
  value       = data.aws_ami.datasync.id
  description = "Resolved DataSync agent AMI"
}

output "filegw_bucket" {
  value = aws_s3_bucket.filegw.bucket
}

output "sgw_role_arn" {
  value = aws_iam_role.storage_gateway.arn
}

output "datasync_min_offered" {
  value = length(data.aws_ec2_instance_type_offerings.datasync_min.instance_types) > 0
}
