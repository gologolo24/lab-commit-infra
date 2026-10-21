terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }

  # Partial config: scripts/tf.sh passes ../backend.hcl plus
  # key = envs/<env>/<stack>/terraform.tfstate (derived from the folder).
  backend "s3" {}
}

# Credentials come from the environment (AWS_PROFILE, set by scripts/tf.sh).
provider "aws" {
  region              = local.env.region
  allowed_account_ids = [local.env.account_id] # refuse to run against any other account

  default_tags {
    tags = {
      Project     = local.env.name
      Environment = local.env.environment
      Owner       = local.env.owner
      ManagedBy   = "terraform"
      Stack       = basename(abspath(path.module))
      Repository  = "github.com/gologolo24/lab-commit-infra"
    }
  }
}
