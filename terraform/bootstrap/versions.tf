terraform {
  # 1.10+ is required for S3 native state locking (use_lockfile).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }

  # Bootstrap runs once per AWS account and stores its state in the bucket it
  # creates (it started with local state and was migrated). Settings: backend.hcl.
  backend "s3" {}
}
