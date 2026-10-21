# Privileged role for all lab work ("assume your Role for privileged access").
#
# - Only one IAM user can assume it, and only with MFA.
# - The session name must equal the IAM user name, so CloudTrail shows who
#   did what inside the role.
# - Credentials are temporary (max 4h by default).

locals {
  admin_trusted_user_arn = "arn:aws:iam::${var.account_id}:user/${var.admin_trusted_user}"
}

data "aws_iam_policy_document" "admin_trust" {
  statement {
    sid     = "AllowLabUserWithMFA"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.admin_trusted_user_arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:RoleSessionName"
      values   = ["$${aws:username}"]
    }
  }
}

resource "aws_iam_role" "admin" {
  name                 = var.admin_role_name
  description          = "Privileged role for the Commit EKS lab. Assumed by ${var.admin_trusted_user} with MFA."
  assume_role_policy   = data.aws_iam_policy_document.admin_trust.json
  max_session_duration = var.admin_max_session_seconds
}

# The lab creates IAM roles, EKS, VPC, RDS, KMS, CodePipeline and more, so this role
# needs full admin. Least privilege applies to everything the lab creates
# (IRSA roles, CodeBuild roles, instance profiles), not to the operator role itself.
resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
