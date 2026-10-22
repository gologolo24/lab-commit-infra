variable "name" {
  description = "Name prefix (unique per account)."
  type        = string
}

variable "environment" {
  description = "Environment the pipelines deploy to: they update apps/<service>/envs/<environment>/values.yaml."
  type        = string
}

variable "services" {
  description = <<-EOT
    One ECR repository and one pipeline per folder in the app repo. The smoke
    test waits until https://<app_fqdn><smoke_path> answers with the new version
    in the JSON field smoke_field.
  EOT
  type = map(object({
    smoke_path  = string
    smoke_field = string
  }))
}

variable "app_repo" {
  description = "GitHub repository with the app source, as owner/name."
  type        = string
}

variable "app_branch" {
  description = "Pushes to this branch start the pipelines."
  type        = string
  default     = "main"
}

variable "gitops_repo_url" {
  description = "GitOps repository (SSH URL). The deploy stage commits image tags to it."
  type        = string
}

variable "gitops_branch" {
  type    = string
  default = "main"
}

variable "gitops_deploy_key_secret_arn" {
  description = "Secrets Manager secret with the GitOps repo's write deploy key (filled by scripts/create-gitops-deploy-keys.sh)."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key that encrypts the deploy key secret."
  type        = string
}

variable "ca_cert_parameter" {
  description = "SSM parameter with the lab CA certificate (the smoke test verifies the ALB's certificate with it)."
  type        = string
  default     = "/lab-commit/tls/ca-cert"
}

variable "app_fqdn" {
  description = "The app's private hostname on the internal ALB."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for the CodeBuild network interfaces."
  type        = list(string)
}

variable "security_group_id" {
  description = "The 'codebuild' security group: outbound 443 and 22 only."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key for the CodeBuild log groups."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "codebuild_image" {
  description = "CodeBuild managed image (x86_64: Fargate runs x86 only, so images are built natively)."
  type        = string
}

variable "image_retention_count" {
  description = "ECR keeps this many images per repository; older ones expire."
  type        = number
  default     = 20
}

variable "smoke_test_timeout_seconds" {
  description = "How long the deploy stage waits for the new version to be live (Argo CD poll + Fargate rollout)."
  type        = number
  default     = 900
}
