# Customer-managed keys. The default key policy (account root) delegates to IAM:
# each instance role gets exactly the kms permissions it needs.

resource "aws_kms_key" "ebs" {
  description             = "${var.name}: EBS volumes of the access instances"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

# Encrypts Session Manager session data end to end (on top of TLS).
resource "aws_kms_key" "ssm_sessions" {
  description             = "${var.name}: Session Manager session encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "ssm_sessions" {
  name          = "alias/${var.name}-ssm-sessions"
  target_key_id = aws_kms_key.ssm_sessions.key_id
}
