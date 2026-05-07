output "kms_key_arn" {
  value = aws_kms_key.lab.arn
}

output "kms_key_id" {
  value = aws_kms_key.lab.key_id
}

output "kms_alias" {
  value = aws_kms_alias.lab.name
}

output "bucket" {
  value = aws_s3_bucket.secure.bucket
}

output "object_key" {
  value = aws_s3_object.secret_file.key
}

output "secret_id" {
  value = aws_secretsmanager_secret.db_pass.id
}
