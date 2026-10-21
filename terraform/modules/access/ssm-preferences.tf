# Session Manager settings for OUR shell sessions only.
#
# The lab AWS account is shared with other candidates. AWS has exactly one
# account-wide default (the document "SSM-SessionManagerRunShell") that applies
# to everyone's sessions. Forcing our KMS key there would break other people's
# sessions (their instances can't use our key), so we leave the default alone.
#
# Instead, our own Session document applies only when a session names it:
#   aws ssm start-session --target <our instance> --document-name lab-commit-shell
# Our shells are then KMS-encrypted (on top of TLS) and logged to CloudWatch.
# Tunnels (EKS API, RDP) use AWS's port-forwarding documents (TLS-encrypted).

resource "aws_cloudwatch_log_group" "ssm_sessions" {
  name              = "/${var.name}/ssm-sessions"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_ssm_document" "shell_session" {
  name            = "${var.name}-shell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "${var.name}: KMS-encrypted, logged shell sessions on the lab instances"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.ssm_sessions.name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      kmsKeyId                    = aws_kms_key.ssm_sessions.key_id
      runAsEnabled                = false
      runAsDefaultUser            = ""
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      shellProfile                = { windows = "", linux = "" }
    }
  })
}
