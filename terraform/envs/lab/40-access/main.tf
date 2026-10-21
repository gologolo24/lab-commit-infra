# lab / 40-access: Windows test client + ops instance (no key pair, no public IP,
# SSM only) and Session Manager preferences. Logic lives in modules/access.
#
# Run with: scripts/tf.sh lab 40-access plan

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

locals {
  network = data.terraform_remote_state.network.outputs
}

module "access" {
  source = "../../../modules/access"

  name                     = local.env.name
  windows_instance_type    = local.env.access.windows_instance_type
  ops_instance_type        = local.env.access.ops_instance_type
  windows_username         = local.env.access.windows_username
  windows_password_version = local.env.access.windows_password_version

  subnet_id                 = local.network.private_subnet_ids[0]
  windows_security_group_id = local.network.security_group_ids["windows"]
  ops_security_group_id     = local.network.security_group_ids["ops"]
  logs_kms_key_arn          = local.network.logs_kms_key_arn

  secrets_kms_key_arn = data.terraform_remote_state.bootstrap.outputs.secrets_kms_key_arn
}
