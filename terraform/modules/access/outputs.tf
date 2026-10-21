output "windows_instance_id" {
  value = aws_instance.this["windows"].id
}

output "ops_instance_id" {
  value = aws_instance.this["ops"].id
}

output "windows_password_secret" {
  description = "Secrets Manager secret with the RDP login (read it yourself; never printed by Terraform)."
  value       = aws_secretsmanager_secret.windows.name
}

output "windows_setup_association_id" {
  value = aws_ssm_association.windows_setup.association_id
}

output "session_log_group" {
  value = aws_cloudwatch_log_group.ssm_sessions.name
}
