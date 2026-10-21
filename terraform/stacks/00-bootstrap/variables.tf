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
  description = "Maximum session length for the admin role. 4 hours covers a long EKS apply."
  type        = number
  default     = 14400

  validation {
    condition     = var.admin_max_session_seconds >= 3600 && var.admin_max_session_seconds <= 43200
    error_message = "Must be between 3600 (1h) and 43200 (12h)."
  }
}
