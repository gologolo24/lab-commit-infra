# lab / 50-cluster-bootstrap: External Secrets, Argo CD repo credentials,
# AWS Load Balancer Controller, external-dns, Argo CD, and the Argo CD projects +
# ApplicationSets. Logic lives in modules/cluster-bootstrap.
#
# Needs the EKS tunnel:   scripts/eks-tunnel.sh   (in another terminal)
# Run with:               scripts/tf.sh lab 50-cluster-bootstrap plan

locals {
  env = yamldecode(file("${path.module}/../env.yaml"))

  tags = {
    Project     = local.env.name
    Environment = local.env.environment
    Owner       = local.env.owner
    ManagedBy   = "terraform"
    Stack       = basename(abspath(path.module))
    Repository  = "github.com/gologolo24/lab-commit-infra"
  }

  network   = data.terraform_remote_state.network.outputs
  eks       = data.terraform_remote_state.eks.outputs
  bootstrap = data.terraform_remote_state.bootstrap.outputs
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

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = local.env.state_bucket
    key    = "envs/${local.env.environment}/20-eks/terraform.tfstate"
    region = local.env.region
  }
}

module "cluster_bootstrap" {
  source = "../../../modules/cluster-bootstrap"

  name        = local.env.name
  environment = local.env.environment
  tags        = { for k, v in local.tags : k => v if k != "ManagedBy" && k != "Stack" }

  vpc_id                = local.network.vpc_id
  zone_id               = local.network.zone_id
  zone_name             = local.network.zone_name
  certificate_arn       = local.network.app_certificate_arn
  alb_security_group_id = local.network.security_group_ids["alb"]

  oidc_provider_arn = local.eks.oidc_provider_arn
  oidc_provider     = local.eks.oidc_provider
  irsa_role_arns    = local.eks.irsa_role_arns

  secrets_kms_key_arn          = local.bootstrap.secrets_kms_key_arn
  argocd_deploy_key_secret_arn = local.bootstrap.gitops_deploy_key_secret_arns["argocd"]

  gitops_repo_url          = local.env.gitops.repo_url
  gitops_revision          = local.env.gitops.revision
  argocd_hostname          = local.env.cluster_bootstrap.argocd_hostname
  chart_versions           = local.env.cluster_bootstrap.charts
  grafana_password_version = local.env.cluster_bootstrap.grafana_password_version
}
