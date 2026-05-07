terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Course    = "archadv"
      Owner     = var.harness_owner
      ManagedBy = "proof-harness"
      Lab       = "07-cicd"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "harness_owner" {
  type    = string
  default = "ci"
}

data "aws_caller_identity" "me" {}

# --- CodeCommit repo (CodeCommit returned to GA in Nov 2025) ---

resource "aws_codecommit_repository" "hello" {
  repository_name = "archadv-${var.harness_owner}-lab07-hello"
  description     = "archadv lab 7 harness"
}

# --- Artifact bucket ---

resource "aws_s3_bucket" "artifacts" {
  bucket        = "archadv-${var.harness_owner}-lab07-artifacts"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- CodeBuild service role ---

resource "aws_iam_role" "codebuild" {
  name = "archadv-${var.harness_owner}-lab07-codebuild"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_inline" {
  name = "lab07-codebuild"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["codecommit:GitPull"]
        Resource = aws_codecommit_repository.hello.arn
      }
    ]
  })
}

# --- CodeBuild project ---

resource "aws_codebuild_project" "hello" {
  name         = "archadv-${var.harness_owner}-lab07-build"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.artifacts.id
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }

  source {
    type      = "CODECOMMIT"
    location  = aws_codecommit_repository.hello.clone_url_http
    buildspec = <<-YAML
      version: 0.2
      phases:
        build:
          commands:
            - echo "archadv lab 7 harness build"
            - echo "build succeeded at $(date)" > build-output.txt
      artifacts:
        files:
          - build-output.txt
    YAML
  }

  depends_on = [aws_iam_role_policy.codebuild_inline]
}

# --- CodePipeline service role ---

resource "aws_iam_role" "pipeline" {
  name = "archadv-${var.harness_owner}-lab07-pipeline"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "pipeline_inline" {
  name = "lab07-pipeline"
  role = aws_iam_role.pipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        # CodeCommit needs permissive resource scope — pipeline calls
        # GetBranch / GetCommit / UploadArchive on both the repo ARN and
        # implicit metadata resources. Scoped to this account.
        Effect   = "Allow"
        Action   = ["codecommit:*"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
        Resource = aws_codebuild_project.hello.arn
      },
      {
        # Pipeline-managed resources (encryption keys, etc.)
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_codepipeline" "hello" {
  name     = "archadv-${var.harness_owner}-lab07-pipeline"
  role_arn = aws_iam_role.pipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source"]
      configuration = {
        RepositoryName = aws_codecommit_repository.hello.repository_name
        BranchName     = "main"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source"]
      output_artifacts = ["build"]
      configuration = {
        ProjectName = aws_codebuild_project.hello.name
      }
    }
  }

  depends_on = [aws_iam_role_policy.pipeline_inline]
}
