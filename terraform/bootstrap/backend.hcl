# Backend for the bootstrap stack itself (one per AWS account). It stores its
# state in the bucket it creates; it started with local state and was migrated.
#   terraform -chdir=terraform/bootstrap init -backend-config=backend.hcl
bucket       = "lab-commit-tfstate-788717064995-us-west-2"
key          = "bootstrap/terraform.tfstate"
region       = "us-west-2"
encrypt      = true
kms_key_id   = "arn:aws:kms:us-west-2:788717064995:key/81c5f5ae-1790-4eff-99bb-ded155c3bb11" # alias/lab-commit-tfstate
use_lockfile = true
