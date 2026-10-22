# One CodePipeline (V2) per service:
#
#   Source  GitHub lab-commit-app, through a CodeConnections connection. A push
#           to main that changes <service>/** starts this pipeline only.
#   Build   CodeBuild <service>-build: tests, image, ECR push, scan check
#   Deploy  CodeBuild <service>-deploy: GitOps commit, wait for the live version
#
# PDF: "Create a CodePipeline that will deploy a new version of the frontend
# service". The backend gets the same pipeline.

# Terraform creates the connection as PENDING. One-time manual step in the
# console: Developer Tools > Settings > Connections > lab-commit-github >
# "Update pending connection", and install the AWS Connector GitHub App on the
# app repository only.
resource "aws_codeconnections_connection" "github" {
  name          = "${var.name}-github"
  provider_type = "GitHub"
}

data "aws_iam_policy_document" "pipeline_trust" {
  for_each = var.services

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:codepipeline:${local.region}:${local.account_id}:${local.pipeline_names[each.key]}"]
    }
  }
}

data "aws_iam_policy_document" "pipeline" {
  for_each = var.services

  statement {
    sid = "GitHubConnectionOnly"
    # Same permission under the service's old and new names.
    actions   = ["codeconnections:UseConnection", "codestar-connections:UseConnection"]
    resources = [aws_codeconnections_connection.github.arn]
  }

  statement {
    sid       = "OwnArtifactsOnly"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/${local.pipeline_names[each.key]}/*"]
  }

  statement {
    sid       = "ArtifactsBucket"
    actions   = ["s3:GetBucketVersioning", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.artifacts.arn]
  }

  statement {
    sid       = "ArtifactsKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.cicd.arn]
  }

  # ARNs built from the names (not the project attributes), so a buildspec
  # change doesn't show up as a policy change in the plan.
  statement {
    sid     = "OwnBuildsOnly"
    actions = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [
      for stage in ["build", "deploy"] :
      "arn:aws:codebuild:${local.region}:${local.account_id}:project/${var.name}-${each.key}-${stage}"
    ]
  }
}

resource "aws_iam_role" "pipeline" {
  for_each = var.services

  name               = "${var.name}-codepipeline-${each.key}"
  description        = "CodePipeline ${local.pipeline_names[each.key]}"
  assume_role_policy = data.aws_iam_policy_document.pipeline_trust[each.key].json
}

resource "aws_iam_role_policy" "pipeline" {
  for_each = var.services

  name   = "${var.name}-codepipeline-${each.key}"
  role   = aws_iam_role.pipeline[each.key].id
  policy = data.aws_iam_policy_document.pipeline[each.key].json
}

resource "aws_codepipeline" "this" {
  for_each = var.services

  name           = local.pipeline_names[each.key]
  pipeline_type  = "V2"
  execution_mode = "QUEUED" # releases run one after another, in order
  role_arn       = aws_iam_role.pipeline[each.key].arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket

    encryption_key {
      type = "KMS"
      id   = aws_kms_key.cicd.arn
    }
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      namespace        = "SourceVariables"
      output_artifacts = ["source"]

      configuration = {
        ConnectionArn    = aws_codeconnections_connection.github.arn
        FullRepositoryId = var.app_repo
        BranchName       = var.app_branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      namespace       = "BuildVariables" # exports IMAGE_TAG
      input_artifacts = ["source"]

      configuration = {
        ProjectName = aws_codebuild_project.build[each.key].name
        EnvironmentVariables = jsonencode([
          { name = "SOURCE_COMMIT", value = "#{SourceVariables.CommitId}", type = "PLAINTEXT" },
        ])
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source"]

      configuration = {
        ProjectName = aws_codebuild_project.deploy[each.key].name
        EnvironmentVariables = jsonencode([
          { name = "IMAGE_TAG", value = "#{BuildVariables.IMAGE_TAG}", type = "PLAINTEXT" },
          { name = "SOURCE_COMMIT", value = "#{SourceVariables.CommitId}", type = "PLAINTEXT" },
        ])
      }
    }
  }

  # Only changes under <service>/ on the release branch start this pipeline.
  trigger {
    provider_type = "CodeStarSourceConnection"

    git_configuration {
      source_action_name = "Source"

      push {
        branches {
          includes = [var.app_branch]
        }
        file_paths {
          includes = ["${each.key}/**"]
        }
      }
    }
  }

  depends_on = [aws_iam_role_policy.pipeline]
}
