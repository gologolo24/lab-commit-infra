variable "name" {
  description = "Cluster name (and prefix for its IAM roles)."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version (PDF: 1.36)."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for the control-plane ENIs and every Fargate pod (PDF: only private subnets)."
  type        = list(string)
}

variable "admin_role_arn" {
  description = "The only cluster administrator (EKS access entry) and KMS key administrator."
  type        = string
}

variable "ops_security_group_id" {
  description = "Security group of the ops instance, the only source allowed to reach the private API endpoint."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key for the control-plane CloudWatch log group."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "fargate_profiles" {
  description = "Fargate profiles: name => namespaces. A profile allows at most 5 namespace selectors."
  type        = map(list(string))

  validation {
    condition     = alltrue([for ns in values(var.fargate_profiles) : length(ns) <= 5])
    error_message = "A Fargate profile allows at most 5 selectors."
  }
}

variable "addon_versions" {
  description = "Pinned EKS add-on versions (check: aws eks describe-addon-versions --kubernetes-version <v>)."
  type = object({
    coredns        = string
    metrics_server = string
  })
}

variable "zone_id" {
  description = "Private hosted zone external-dns may change (and nothing else)."
  type        = string
}
