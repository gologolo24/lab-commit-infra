output "argocd_url" {
  value = module.cluster_bootstrap.argocd_url
}

output "eso_role_arns" {
  value = module.cluster_bootstrap.eso_role_arns
}

output "argocd_reviewer_secret" {
  value = module.cluster_bootstrap.argocd_reviewer_secret
}

output "grafana_admin_secret" {
  value = module.cluster_bootstrap.grafana_admin_secret
}

output "alb_ingress_annotations" {
  value = module.cluster_bootstrap.alb_ingress_annotations
}
