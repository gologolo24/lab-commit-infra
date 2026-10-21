output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "The two private subnets (EKS, Fargate, RDS, EC2, endpoints)."
  value       = [for s in aws_subnet.private : s.id]
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.regional.id
}

output "security_group_ids" {
  description = "Security group IDs by purpose (alb, windows, ops, rds, backend-pods, loadgen-pods, codebuild, vpce)."
  value       = { for k, sg in aws_security_group.this : k => sg.id }
}

output "zone_id" {
  value = aws_route53_zone.private.zone_id
}

output "zone_name" {
  value = aws_route53_zone.private.name
}

output "app_fqdn" {
  description = "The application URL host (PDF: Lab-commit-task.<your-hosted-zone>)."
  value       = "${var.app_hostname}.${var.zone_name}"
}

output "app_certificate_arn" {
  description = "Imported self-signed certificate for the internal ALB."
  value       = data.aws_acm_certificate.app.arn
}

output "logs_kms_key_arn" {
  description = "Shared KMS key for CloudWatch Logs groups in later stacks."
  value       = aws_kms_key.logs.arn
}
