variable "name" {
  description = "DB instance identifier and name prefix (unique per account)."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the DB subnet group (two AZs)."
  type        = list(string)
}

variable "security_group_id" {
  description = "The 'rds' security group: 5432 only from backend pods."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major version (RDS picks the recommended minor)."
  type        = string
}

variable "instance_class" {
  type = string
}

variable "allocated_storage_gb" {
  type = number
}

variable "multi_az" {
  description = "Standby in a second AZ. Lab: false (cost). Production: true."
  type        = bool
}

variable "db_name" {
  description = "Database created with the instance."
  type        = string
}

variable "master_username" {
  description = "Master user. Its password is generated and stored by RDS in Secrets Manager."
  type        = string
  default     = "labadmin"
}

variable "app_user" {
  description = "Read-only application user that logs in with IAM tokens (created by the db-migrate job)."
  type        = string
}

variable "backup_retention_days" {
  description = "Automated backups. Backup storage up to the DB size is free, so 7 days costs ~nothing."
  type        = number
  default     = 7
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "logs_kms_key_arn" {
  description = "KMS key for the PostgreSQL CloudWatch log group."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key for the RDS-managed master password secret."
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider (IRSA)."
  type        = string
}

variable "oidc_provider" {
  description = "EKS OIDC issuer without https://."
  type        = string
}

variable "app_namespace" {
  description = "Kubernetes namespace of the backend and db-migrate service accounts."
  type        = string
}
