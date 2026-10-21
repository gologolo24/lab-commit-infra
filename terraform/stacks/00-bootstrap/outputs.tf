output "admin_role_arn" {
  description = "Put this in the commit-lab profile (role_arn) in ~/.aws/config."
  value       = aws_iam_role.admin.arn
}
