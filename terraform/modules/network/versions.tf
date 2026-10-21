# Reusable module: no provider configuration and no backend here. Those belong
# to the environment root modules in terraform/envs/<env>/.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.69" # regional NAT gateway (availability_mode)
    }
  }
}

# Account and region come from the caller's provider, so the module works in any account.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}
