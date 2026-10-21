output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Private API endpoint (reachable only inside the VPC)."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "cluster_primary_security_group_id" {
  description = "EKS-managed SG that every Fargate pod gets. Include it in every SecurityGroupPolicy."
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_security_group_id" {
  description = "Control-plane SG created by the module (443 from the ops instance)."
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "OIDC issuer without https://, for IRSA trust policies in later stacks."
  value       = module.eks.oidc_provider
}

output "kms_key_arn" {
  description = "KMS key that encrypts Kubernetes Secrets."
  value       = module.eks.kms_key_arn
}

output "irsa_role_arns" {
  description = "IRSA role ARNs for the service account annotation eks.amazonaws.com/role-arn."
  value = {
    aws_load_balancer_controller = module.irsa_aws_load_balancer_controller.arn
    external_dns                 = module.irsa_external_dns.arn
  }
}
