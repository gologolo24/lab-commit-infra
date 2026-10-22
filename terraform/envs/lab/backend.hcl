# State backend for the "lab" environment: the state bucket of lab's AWS account
# (created by terraform/bootstrap). scripts/tf.sh adds the per-stack key:
#   key = envs/lab/<stack>/terraform.tfstate
bucket       = "lab-commit-tfstate-788717064995-us-west-2"
region       = "us-west-2"
encrypt      = true
kms_key_id   = "arn:aws:kms:us-west-2:788717064995:key/81c5f5ae-1790-4eff-99bb-ded155c3bb11" # alias/lab-commit-tfstate
use_lockfile = true # S3 native locking (.tflock), no DynamoDB
