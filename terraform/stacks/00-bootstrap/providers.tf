# Credentials come from the environment (AWS_PROFILE), never from this file.
# 00-bootstrap is the only stack applied as the IAM user (AWS_PROFILE=commit-base),
# because it creates the privileged role that every other stack runs as.
provider "aws" {
  region = var.region

  # Safety net: refuse to run against any other account.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project     = "lab-commit"
      Environment = "lab"
      ManagedBy   = "terraform"
      Stack       = "00-bootstrap"
      Repository  = "github.com/gologolo24/lab-commit-infra"
    }
  }
}
