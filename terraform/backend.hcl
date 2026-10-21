# Shared S3 backend settings for every stack (created by stacks/00-bootstrap).
# Each stack only sets its own `key`; init with:
#   terraform init -backend-config=../../backend.hcl
bucket       = "lab-commit-tfstate-788717064995"
region       = "us-east-1"
encrypt      = true
kms_key_id   = "arn:aws:kms:us-east-1:788717064995:key/5ca99a5c-0553-4293-ae03-4601c31d9733" # alias/lab-commit-tfstate
use_lockfile = true # S3 native locking (.tflock), no DynamoDB
