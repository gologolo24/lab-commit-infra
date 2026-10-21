variable "name" {
  description = "Name prefix (unique per account)."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for both instances."
  type        = string
}

variable "windows_security_group_id" {
  description = "SG 'windows': no inbound, outbound HTTPS only."
  type        = string
}

variable "ops_security_group_id" {
  description = "SG 'ops': no inbound, outbound HTTPS inside the VPC only."
  type        = string
}

variable "windows_instance_type" {
  type = string
}

variable "ops_instance_type" {
  type = string
}

variable "windows_ami_parameter" {
  description = "Public SSM parameter with the latest Windows Server AMI."
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2025-English-Full-Base"
}

variable "ops_ami_parameter" {
  description = "Public SSM parameter with the latest Amazon Linux 2023 (arm64) AMI."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

variable "windows_username" {
  description = "Local RDP user (member of Remote Desktop Users only)."
  type        = string
}

variable "windows_password_version" {
  description = "Bump to generate and store a new Windows password."
  type        = number
}

variable "ca_cert_parameter" {
  description = "SSM parameter with the lab root CA certificate (public), trusted by Windows."
  type        = string
  default     = "/lab-commit/tls/ca-cert"
}

variable "chrome_start_urls" {
  description = "Pages Chrome opens on start."
  type        = list(string)
}

variable "logs_kms_key_arn" {
  description = "KMS key for the Session Manager CloudWatch log group."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key for the Windows password secret."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}
