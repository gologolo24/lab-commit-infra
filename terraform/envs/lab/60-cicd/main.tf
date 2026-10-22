# lab / 60-cicd: ECR repositories and one CodePipeline per service (GitHub ->
# CodeBuild tests + image -> ECR -> GitOps commit -> Argo CD -> smoke test).
# Logic lives in modules/cicd.
#
# Run with: scripts/tf.sh lab 60-cicd plan
# After the first apply: complete the GitHub connection in the console (see
# modules/cicd/pipeline.tf).

locals {
  env = yamldecode(file("${path.module}/../env.yaml"))
}

data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket = local.env.state_bucket
    key    = "bootstrap/terraform.tfstate"
    region = local.env.region
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = local.env.state_bucket
    key    = "envs/${local.env.environment}/10-network/terraform.tfstate"
    region = local.env.region
  }
}

module "cicd" {
  source = "../../../modules/cicd"

  name                       = local.env.name
  environment                = local.env.environment
  services                   = local.env.cicd.services
  app_repo                   = local.env.cicd.app_repo
  app_branch                 = local.env.cicd.app_branch
  codebuild_image            = local.env.cicd.codebuild_image
  image_retention_count      = local.env.cicd.image_retention_count
  smoke_test_timeout_seconds = local.env.cicd.smoke_test_timeout_seconds

  gitops_repo_url              = local.env.gitops.repo_url
  gitops_branch                = local.env.gitops.revision
  gitops_deploy_key_secret_arn = data.terraform_remote_state.bootstrap.outputs.gitops_deploy_key_secret_arns["codebuild"]
  secrets_kms_key_arn          = data.terraform_remote_state.bootstrap.outputs.secrets_kms_key_arn

  app_fqdn          = data.terraform_remote_state.network.outputs.app_fqdn
  vpc_id            = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids        = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_id = data.terraform_remote_state.network.outputs.security_group_ids["codebuild"]
  logs_kms_key_arn  = data.terraform_remote_state.network.outputs.logs_kms_key_arn
}
