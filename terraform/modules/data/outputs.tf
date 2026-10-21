output "db_address" {
  description = "Private DNS name of the DB (resolves only inside the VPC)."
  value       = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_resource_id" {
  description = "Used in rds-db:connect ARNs."
  value       = aws_db_instance.this.resource_id
}

output "master_username" {
  value = aws_db_instance.this.username
}

output "master_secret_arn" {
  description = "Secrets Manager secret with the RDS-managed master password (value never in state)."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "app_user" {
  value = var.app_user
}

output "kms_key_arn" {
  value = aws_kms_key.rds.arn
}

output "irsa_role_arns" {
  description = "IRSA role ARNs for the service account annotation eks.amazonaws.com/role-arn."
  value = {
    backend     = module.irsa_backend.arn
    db_migrator = module.irsa_db_migrator.arn
  }
}
