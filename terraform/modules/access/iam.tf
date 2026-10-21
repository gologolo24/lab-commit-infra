# One role per instance. Both get AmazonSSMManagedInstanceCore (SSM agent) and may
# write their own session logs. Only Windows may read its password secret and the CA.

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "session_logging" {
  statement {
    sid       = "WriteSessionLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.ssm_sessions.arn}:*"]
  }

  statement {
    sid       = "FindLogGroup"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:*"]
  }

  statement {
    sid       = "DecryptSessionData"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.ssm_sessions.arn]
  }
}

data "aws_iam_policy_document" "windows_setup" {
  statement {
    sid       = "ReadOwnPasswordOnly"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.windows.arn]
  }

  statement {
    sid       = "DecryptViaSecretsManagerOnly"
    actions   = ["kms:Decrypt"]
    resources = [var.secrets_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadLabCaCertificate"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${local.region}:${local.account_id}:parameter${var.ca_cert_parameter}"]
  }
}

locals {
  instance_roles = {
    windows = "Windows test client (Chrome): SSM, its own password secret, the lab CA"
    ops     = "Ops instance: SSM only (port forwarding to the private EKS API)"
  }
}

resource "aws_iam_role" "instance" {
  for_each = local.instance_roles

  name               = "${var.name}-${each.key}"
  description        = each.value
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  for_each = local.instance_roles

  role       = aws_iam_role.instance[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "session_logging" {
  for_each = local.instance_roles

  name   = "session-logging"
  role   = aws_iam_role.instance[each.key].id
  policy = data.aws_iam_policy_document.session_logging.json
}

resource "aws_iam_role_policy" "windows_setup" {
  name   = "windows-setup"
  role   = aws_iam_role.instance["windows"].id
  policy = data.aws_iam_policy_document.windows_setup.json
}

resource "aws_iam_instance_profile" "instance" {
  for_each = local.instance_roles

  name = "${var.name}-${each.key}"
  role = aws_iam_role.instance[each.key].name
}
