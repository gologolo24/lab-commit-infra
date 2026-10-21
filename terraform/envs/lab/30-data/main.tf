# lab / 30-data: RDS PostgreSQL (private, encrypted, TLS-only, IAM auth) and
# the IRSA roles for the backend and the db-migrate job. Logic lives in modules/data.
#
# Run with: scripts/tf.sh lab 30-data plan

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

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = local.env.state_bucket
    key    = "envs/${local.env.environment}/20-eks/terraform.tfstate"
    region = local.env.region
  }
}

module "data" {
  source = "../../../modules/data"

  name                 = local.env.name
  engine_version       = local.env.data.engine_version
  instance_class       = local.env.data.instance_class
  allocated_storage_gb = local.env.data.allocated_storage_gb
  multi_az             = local.env.data.multi_az
  db_name              = local.env.data.db_name
  app_user             = local.env.data.app_user
  app_namespace        = local.env.app.namespace

  subnet_ids        = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_id = data.terraform_remote_state.network.outputs.security_group_ids["rds"]
  logs_kms_key_arn  = data.terraform_remote_state.network.outputs.logs_kms_key_arn

  secrets_kms_key_arn = data.terraform_remote_state.bootstrap.outputs.secrets_kms_key_arn

  oidc_provider_arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  oidc_provider     = data.terraform_remote_state.eks.outputs.oidc_provider
}
