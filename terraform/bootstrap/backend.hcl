# Backend for the bootstrap stack itself (one per AWS account). It stores its
# state in the bucket it creates; it started with local state and was migrated.
#   terraform -chdir=terraform/bootstrap init -backend-config=backend.hcl
bucket       = "lab-commit-tfstate-788717064995"
key          = "bootstrap/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
kms_key_id   = "arn:aws:kms:us-east-1:788717064995:key/5ca99a5c-0553-4293-ae03-4601c31d9733" # alias/lab-commit-tfstate
use_lockfile = true
