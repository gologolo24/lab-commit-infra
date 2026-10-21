terraform {
  # 1.10+ is required for S3 native state locking (use_lockfile).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }

  # This stack creates the bucket it stores its own state in. It started with
  # local state and was migrated with -migrate-state once the bucket existed.
  backend "s3" {
    key = "stacks/00-bootstrap/terraform.tfstate"
  }
}
