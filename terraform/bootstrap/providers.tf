# Credentials come from the environment, never from this file:
#   AWS_PROFILE=commit-lab   (the lab-commit-admin role, with MFA)
#
# The very first apply (which created the admin role) ran as the IAM user
# (AWS_PROFILE=commit-base). Since then this stack runs as the role too.
provider "aws" {
  region = var.region

  # Safety net: refuse to run against any other account.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project     = "lab-commit"
      Environment = "lab"
      Owner       = var.owner
      ManagedBy   = "terraform"
      Stack       = "bootstrap"
      Repository  = "github.com/gologolo24/lab-commit-infra"
    }
  }
}
