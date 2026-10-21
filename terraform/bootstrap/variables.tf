variable "region" {
  description = "AWS region for the whole lab."
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "The Commit lab AWS account. The provider refuses to run anywhere else."
  type        = string
  default     = "788717064995"
}

variable "owner" {
  description = "Owner tag on every resource."
  type        = string
  default     = "leib"
}

variable "github_owner" {
  description = "GitHub account that owns the lab repositories."
  type        = string
  default     = "gologolo24"
}

variable "gitops_repo" {
  description = "GitOps repository that Argo CD reads and CodeBuild updates."
  type        = string
  default     = "lab-commit-gitops"
}

variable "kms_deletion_window_days" {
  description = "Waiting period before a scheduled KMS key deletion. Short because this is a lab."
  type        = number
  default     = 7
}

variable "admin_trusted_user" {
  description = "IAM user allowed to assume the privileged admin role (with MFA)."
  type        = string
  default     = "candidate03"
}

variable "admin_role_name" {
  description = "Name of the privileged role used for all lab work."
  type        = string
  default     = "lab-commit-admin"
}

variable "admin_max_session_seconds" {
  # Note: sessions started from `aws login` credentials count as role chaining,
  # which AWS always caps at 1 hour regardless of this value.
  description = "Maximum session length for the admin role (applies when not role chaining)."
  type        = number
  default     = 14400

  validation {
    condition     = var.admin_max_session_seconds >= 3600 && var.admin_max_session_seconds <= 43200
    error_message = "Must be between 3600 (1h) and 43200 (12h)."
  }
}
