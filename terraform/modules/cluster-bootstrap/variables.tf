variable "name" {
  description = "Name prefix (unique per account); also the EKS cluster name."
  type        = string
}

variable "environment" {
  description = "Environment label on the in-cluster Argo CD cluster secret (the ApplicationSets select on it)."
  type        = string
}

variable "tags" {
  description = "Tags the AWS Load Balancer Controller puts on every ALB it creates."
  type        = map(string)
}

variable "vpc_id" {
  type = string
}

variable "zone_id" {
  description = "Private hosted zone external-dns writes to (and nothing else)."
  type        = string
}

variable "zone_name" {
  type = string
}

variable "certificate_arn" {
  description = "ACM certificate (self-signed CA) for the internal ALB."
  type        = string
}

variable "alb_security_group_id" {
  description = "SG 'alb': 443 only from the Windows client, load generator pods and CodeBuild."
  type        = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider" {
  description = "EKS OIDC issuer without https://."
  type        = string
}

variable "irsa_role_arns" {
  description = "IRSA roles from the EKS stack: aws_load_balancer_controller, external_dns."
  type        = map(string)
}

variable "secrets_kms_key_arn" {
  description = "KMS key of the Secrets Manager secrets (decrypt allowed via Secrets Manager only)."
  type        = string
}

variable "argocd_deploy_key_secret_arn" {
  description = "Secrets Manager secret with Argo CD's read-only SSH deploy key for the GitOps repo."
  type        = string
}

variable "gitops_repo_url" {
  description = "GitOps repository (SSH URL)."
  type        = string
}

variable "gitops_revision" {
  type = string
}

variable "argocd_hostname" {
  description = "Host label of the Argo CD UI (-> <label>.<zone>)."
  type        = string
}

variable "chart_versions" {
  description = "Pinned Helm chart versions."
  type = object({
    external_secrets             = string
    aws_load_balancer_controller = string
    external_dns                 = string
    argo_cd                      = string
    argocd_apps                  = string
  })
}

variable "grafana_password_version" {
  description = "Bump to generate and store a new Grafana admin password."
  type        = number
}

variable "platform_chart_repos" {
  description = "Upstream Helm repositories the 'platform' AppProject may deploy from."
  type        = list(string)
  default = [
    "https://prometheus-community.github.io/helm-charts",
    "https://kedacore.github.io/charts",
  ]
}

variable "platform_namespaces" {
  description = "Namespaces the 'platform' AppProject may deploy to."
  type        = list(string)
  # kube-system: KEDA needs one RoleBinding there (its metrics API server must read
  # the API server's auth settings, extension-apiserver-authentication-reader), and
  # kube-prometheus-stack adds a Service there to scrape CoreDNS. The project still
  # only accepts charts from the GitOps repo and the approved chart repositories.
  default = ["monitoring", "keda", "kube-system"]
}

variable "app_namespaces" {
  description = "Namespaces the 'apps' AppProject may deploy to."
  type        = list(string)
  default     = ["lab-commit", "loadgen"]
}
