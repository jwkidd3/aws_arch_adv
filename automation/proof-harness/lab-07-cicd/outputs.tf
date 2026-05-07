output "repo_name" {
  value = aws_codecommit_repository.hello.repository_name
}

output "repo_clone_url_http" {
  value = aws_codecommit_repository.hello.clone_url_http
}

output "build_project" {
  value = aws_codebuild_project.hello.name
}

output "pipeline_name" {
  value = aws_codepipeline.hello.name
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}
