# IRSA (IAM Roles for Service Accounts): one IAM role that exactly ONE
# Kubernetes service account can assume, through the cluster's OIDC provider.
# Fargate doesn't support EKS Pod Identity (it needs a DaemonSet), so IRSA it is.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.69"
    }
  }
}

variable "name" {
  description = "IAM role name."
  type        = string
}

variable "description" {
  description = "What the role is for."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider."
  type        = string
}

variable "oidc_provider" {
  description = "Cluster OIDC issuer without https:// (oidc.eks.<region>.amazonaws.com/id/<id>)."
  type        = string
}

variable "namespace" {
  description = "Namespace of the service account."
  type        = string
}

variable "service_account" {
  description = "Name of the service account allowed to assume the role."
  type        = string
}

variable "policy_json" {
  description = "Permissions of the role (IAM policy document JSON)."
  type        = string
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # Only this one service account in this one namespace...
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
    }

    # ...and only tokens meant for STS.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  description        = var.description
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = var.description
  policy      = var.policy_json
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

output "arn" {
  description = "Role ARN, for the service account annotation eks.amazonaws.com/role-arn."
  value       = aws_iam_role.this.arn
}

output "name" {
  value = aws_iam_role.this.name
}
