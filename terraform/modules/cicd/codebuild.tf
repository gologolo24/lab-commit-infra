# Two CodeBuild projects per service, both in the VPC (private subnets, the
# 'codebuild' security group, internet only through the NAT gateway):
#
#   <service>-build   tests, builds and pushes the image. Its role may push to
#                     its own ECR repository only.
#   <service>-deploy  commits the new image tag to the GitOps repo, then waits
#                     until the app serves the new version. Its role may read
#                     the GitOps write key and the lab CA, nothing else. It has
#                     no cluster access: Argo CD pulls the change.
#
# The buildspecs live here (not in the app repo), so app code changes cannot
# change what the pipeline does with its permissions.

locals {
  projects = merge(
    { for s, _ in var.services : "${s}-build" => { service = s, stage = "build" } },
    { for s, _ in var.services : "${s}-deploy" => { service = s, stage = "deploy" } },
  )

  # CodePipeline stores each pipeline's artifacts under <pipeline name>/ in the bucket.
  pipeline_names = { for s, _ in var.services : s => "${var.name}-${s}" }

  # Pinned tool for the deploy stage (checksum from the release's checksums file).
  yq_version = "v4.54.1"
  yq_sha256  = "8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f"

  # GitHub's published SSH host key (api.github.com/meta), so git push never
  # trusts an unknown host.
  github_ssh_host_key = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"

  # CodeBuild resolves SECRETS_MANAGER variables by secret name.
  gitops_deploy_key_secret_name = regex("secret:(.+)-[A-Za-z0-9]{6}$", var.gitops_deploy_key_secret_arn)[0]
  ca_cert_parameter_arn         = "arn:aws:ssm:${local.region}:${local.account_id}:parameter${var.ca_cert_parameter}"
}

resource "aws_cloudwatch_log_group" "codebuild" {
  for_each = local.projects

  name              = "/${var.name}/codebuild/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

# Confused-deputy protection: CodeBuild may assume each role only for its own project.
data "aws_iam_policy_document" "codebuild_trust" {
  for_each = local.projects

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:codebuild:${local.region}:${local.account_id}:project/${var.name}-${each.key}"]
    }
  }
}

# What every project needs: its own log group, its pipeline's artifacts, and
# network interfaces in the private subnets.
# The ec2:Describe* calls and CreateNetworkInterface don't support resource
# scoping (AWS-0057); creating the interface is limited to the given subnets below.
#trivy:ignore:AVD-AWS-0057
data "aws_iam_policy_document" "codebuild_common" {
  for_each = local.projects

  statement {
    sid       = "OwnLogGroupOnly"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.codebuild[each.key].arn}:*"]
  }

  statement {
    sid       = "OwnPipelineArtifactsReadOnly"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.artifacts.arn}/${local.pipeline_names[each.value.service]}/*"]
  }

  statement {
    sid       = "ArtifactsKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.cicd.arn]
  }

  statement {
    sid = "VpcNetworkInterfaces"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "NetworkInterfacesInOurSubnetsOnly"
    actions   = ["ec2:CreateNetworkInterfacePermission"]
    resources = ["arn:aws:ec2:${local.region}:${local.account_id}:network-interface/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"
      values   = ["codebuild.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "ec2:Subnet"
      values   = [for id in var.subnet_ids : "arn:aws:ec2:${local.region}:${local.account_id}:subnet/${id}"]
    }
  }
}

# Build: push to its own repository only. GetAuthorizationToken has no
# resource-level scoping (AWS-0057).
#trivy:ignore:AVD-AWS-0057
data "aws_iam_policy_document" "build" {
  for_each = var.services

  source_policy_documents = [data.aws_iam_policy_document.codebuild_common["${each.key}-build"].json]

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "OwnRepositoryOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImageScanFindings",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.this[each.key].arn]
  }
}

# Deploy: the GitOps write key and the lab CA certificate, nothing else.
data "aws_iam_policy_document" "deploy" {
  for_each = var.services

  source_policy_documents = [data.aws_iam_policy_document.codebuild_common["${each.key}-deploy"].json]

  statement {
    sid       = "GitopsWriteKeyOnly"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.gitops_deploy_key_secret_arn]
  }

  statement {
    sid       = "DecryptViaSecretsManagerOnly"
    actions   = ["kms:Decrypt"]
    resources = [var.secrets_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "LabCaCertificateOnly"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [local.ca_cert_parameter_arn]
  }
}

resource "aws_iam_role" "codebuild" {
  for_each = local.projects

  name               = "${var.name}-codebuild-${each.key}"
  description        = "CodeBuild ${var.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.codebuild_trust[each.key].json
}

resource "aws_iam_role_policy" "codebuild" {
  for_each = local.projects

  name = "${var.name}-codebuild-${each.key}"
  role = aws_iam_role.codebuild[each.key].id
  policy = (each.value.stage == "build"
    ? data.aws_iam_policy_document.build[each.value.service].json
    : data.aws_iam_policy_document.deploy[each.value.service].json
  )
}

resource "aws_codebuild_project" "build" {
  for_each = var.services

  name           = "${var.name}-${each.key}-build"
  description    = "${each.key}: lint + tests, build the linux/amd64 image (tag = ${each.key}/VERSION), push to ECR, check the scan"
  service_role   = aws_iam_role.codebuild["${each.key}-build"].arn
  build_timeout  = 30
  queued_timeout = 60
  encryption_key = aws_kms_key.cicd.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspecs/build.yml")
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type                        = "LINUX_CONTAINER"
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = var.codebuild_image
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true # docker build

    environment_variable {
      name  = "SERVICE"
      value = each.key
    }
    environment_variable {
      name  = "ECR_REPOSITORY_NAME"
      value = aws_ecr_repository.this[each.key].name
    }
    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = aws_ecr_repository.this[each.key].repository_url
    }
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE"]
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild["${each.key}-build"].name
    }
    s3_logs {
      status = "DISABLED"
    }
  }

  # CodeBuild checks the VPC settings with the role when the project is created.
  depends_on = [aws_iam_role_policy.codebuild]
}

resource "aws_codebuild_project" "deploy" {
  for_each = var.services

  name           = "${var.name}-${each.key}-deploy"
  description    = "${each.key}: commit the image tag to the GitOps repo, then wait until the app serves it"
  service_role   = aws_iam_role.codebuild["${each.key}-deploy"].arn
  build_timeout  = 30
  queued_timeout = 60
  encryption_key = aws_kms_key.cicd.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspecs/deploy.yml")
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type                        = "LINUX_CONTAINER"
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = var.codebuild_image
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "SERVICE"
      value = each.key
    }
    environment_variable {
      name  = "ENVIRONMENT"
      value = var.environment
    }
    environment_variable {
      name  = "PIPELINE_NAME"
      value = local.pipeline_names[each.key]
    }
    environment_variable {
      name  = "GITOPS_REPO"
      value = var.gitops_repo_url
    }
    environment_variable {
      name  = "GITOPS_BRANCH"
      value = var.gitops_branch
    }
    environment_variable {
      name  = "GITHUB_SSH_HOST_KEY"
      value = local.github_ssh_host_key
    }
    environment_variable {
      name  = "GITOPS_DEPLOY_KEY" # fetched at build start, masked in the logs
      type  = "SECRETS_MANAGER"
      value = local.gitops_deploy_key_secret_name
    }
    environment_variable {
      name  = "LAB_CA_CERT"
      type  = "PARAMETER_STORE"
      value = var.ca_cert_parameter
    }
    environment_variable {
      name  = "APP_URL"
      value = "https://${var.app_fqdn}"
    }
    environment_variable {
      name  = "SMOKE_PATH"
      value = each.value.smoke_path
    }
    environment_variable {
      name  = "SMOKE_FIELD"
      value = each.value.smoke_field
    }
    environment_variable {
      name  = "SMOKE_TIMEOUT_SECONDS"
      value = tostring(var.smoke_test_timeout_seconds)
    }
    environment_variable {
      name  = "YQ_VERSION"
      value = local.yq_version
    }
    environment_variable {
      name  = "YQ_SHA256"
      value = local.yq_sha256
    }
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild["${each.key}-deploy"].name
    }
    s3_logs {
      status = "DISABLED"
    }
  }

  depends_on = [aws_iam_role_policy.codebuild]
}
