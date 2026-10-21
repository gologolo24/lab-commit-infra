# lab / 20-eks: EKS 1.36 on Fargate only, private endpoint, IRSA roles for
# the AWS Load Balancer Controller and external-dns. Logic lives in modules/eks.
#
# Run with: scripts/tf.sh lab 20-eks plan

locals {
  env = yamldecode(file("${path.module}/../env.yaml"))
}

# Outputs of earlier stacks, read from their state in S3 (read-only).
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

locals {
  network = data.terraform_remote_state.network.outputs
}

module "eks" {
  source = "../../../modules/eks"

  name               = local.env.name
  kubernetes_version = local.env.eks.kubernetes_version
  fargate_profiles   = local.env.eks.fargate_profiles
  addon_versions     = local.env.eks.addon_versions

  vpc_id                = local.network.vpc_id
  subnet_ids            = local.network.private_subnet_ids
  ops_security_group_id = local.network.security_group_ids["ops"]
  logs_kms_key_arn      = local.network.logs_kms_key_arn
  zone_id               = local.network.zone_id

  admin_role_arn = data.terraform_remote_state.bootstrap.outputs.admin_role_arn
}
