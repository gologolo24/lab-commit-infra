terraform {
  # 1.10+ is required later for S3 native state locking (use_lockfile).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }

  # Local state for now. Step C creates the S3 state bucket and migrates
  # this state into it (terraform init -migrate-state).
}
