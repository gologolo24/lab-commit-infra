# Environment-specific values have no defaults: each environment sets them in
# terraform/envs/<env>/env.yaml. Defaults below are generic module choices.

variable "name" {
  description = "Resource name prefix. Must be unique per AWS account (for example lab-commit, lab-commit-prod)."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC address range."
  type        = string
}

# Exactly two private subnets (PDF: "VPC + 2 Private Subnets").
# Size them generously: every Fargate pod and interface endpoint takes one IP.
variable "private_subnets" {
  description = "Private subnets, one per availability zone: { key = { az, cidr } }."
  type = map(object({
    az   = string
    cidr = string
  }))

  validation {
    condition     = length(var.private_subnets) == 2
    error_message = "This design uses exactly 2 private subnets."
  }
}

variable "zone_name" {
  description = "Private Route 53 hosted zone. Names resolve only inside the VPC."
  type        = string
}

variable "app_hostname" {
  description = "App host label (PDF: Lab-commit-task.<your-hosted-zone>). Its certificate comes from scripts/create-tls-cert.sh."
  type        = string
}

variable "interface_endpoints" {
  description = "AWS services reached through interface VPC endpoints instead of the NAT gateway."
  type        = set(string)
  default = [
    "ecr.api",        # image metadata (Fargate image pulls)
    "ecr.dkr",        # image layers (Fargate image pulls)
    "sts",            # IRSA: pods exchange their token for AWS credentials
    "logs",           # CloudWatch Logs (flow logs, EKS, CodeBuild, SSM sessions)
    "ssm",            # Systems Manager (Windows + ops instance)
    "ssmmessages",    # Session Manager / port forwarding
    "ec2messages",    # SSM agent messaging
    "secretsmanager", # External Secrets Operator, CodeBuild deploy key
  ]
}

variable "alb_target_ports" {
  description = "Container ports the internal ALB may reach: frontend 8080, Argo CD server 8080, Grafana 3000."
  type        = set(number)
  default     = [8080, 3000]
}

variable "log_retention_days" {
  description = "Retention for VPC flow logs."
  type        = number
  default     = 30
}
