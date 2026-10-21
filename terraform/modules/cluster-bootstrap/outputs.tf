output "argocd_url" {
  value = "https://${local.argocd_fqdn}"
}

output "eso_role_arns" {
  description = "IRSA roles of the per-namespace SecretStores (the monitoring one is used from the GitOps repo)."
  value       = { for ns, m in module.irsa_eso_store : ns => m.arn }
}

output "grafana_admin_secret" {
  description = "Secrets Manager secret with the Grafana admin login (value never in state)."
  value       = aws_secretsmanager_secret.grafana_admin.name
}

output "alb_ingress_annotations" {
  description = "Annotations every Ingress uses to join the shared internal ALB (copy into GitOps values)."
  value       = local.alb_ingress_annotations
}
