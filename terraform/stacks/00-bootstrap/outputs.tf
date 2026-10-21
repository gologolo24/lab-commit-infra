output "admin_role_arn" {
  description = "Put this in the commit-lab-mfa profile (role_arn) in ~/.aws/config."
  value       = aws_iam_role.admin.arn
}

output "state_bucket" {
  description = "S3 bucket that holds the state of every stack."
  value       = aws_s3_bucket.tfstate.id
}

output "state_kms_key_arn" {
  description = "KMS key for Terraform state (used as kms_key_id in terraform/backend.hcl)."
  value       = aws_kms_key.tfstate.arn
}

output "secrets_kms_key_arn" {
  description = "KMS key for Secrets Manager secrets."
  value       = aws_kms_key.secrets.arn
}

output "gitops_deploy_key_secret_arns" {
  description = "Secrets Manager ARNs of the GitOps deploy keys, per consumer."
  value       = { for k, s in aws_secretsmanager_secret.gitops_deploy_key : k => s.arn }
}
