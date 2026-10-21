# Reusable module: no provider configuration and no backend here.
terraform {
  required_version = ">= 1.11" # write-only arguments (secret_string_wo)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.69"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7" # ephemeral random_password
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}
