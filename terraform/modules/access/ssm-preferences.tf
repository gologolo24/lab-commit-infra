# Session Manager preferences for this account and region: every shell session
# is KMS-encrypted and logged to CloudWatch, idle sessions close after 20 min.
# (This document name is fixed by AWS; it didn't exist in the account before.)

resource "aws_cloudwatch_log_group" "ssm_sessions" {
  name              = "/${var.name}/ssm-sessions"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_ssm_document" "session_preferences" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences (${var.name})"
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
