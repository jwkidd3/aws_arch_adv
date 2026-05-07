output "lake_bucket" {
  value = aws_s3_bucket.lake.bucket
}

output "results_bucket" {
  value = aws_s3_bucket.results.bucket
}

output "db_name" {
  value = aws_glue_catalog_database.lake.name
}

output "crawler_name" {
  value = aws_glue_crawler.sales.name
}

output "workgroup_name" {
  value = aws_athena_workgroup.lab.name
}
