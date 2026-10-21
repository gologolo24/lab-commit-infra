# Windows RDP password: generated as an *ephemeral* value and written with a
# *write-only* argument, so it never appears in Terraform state or plan output.
# It lives only in Secrets Manager. Rotate by bumping windows_password_version.

resource "aws_secretsmanager_secret" "windows" {
  name                    = "${var.name}/windows/${var.windows_username}"
  description             = "RDP login for the ${var.name} Windows test client (Fleet Manager / RDP tunnel)"
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = 7
}

ephemeral "random_password" "windows" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!#%*+-=?@_" # no quotes, $ or backtick: safe inside PowerShell
}

resource "aws_secretsmanager_secret_version" "windows" {
  secret_id = aws_secretsmanager_secret.windows.id
  secret_string_wo = jsonencode({
    username = var.windows_username
    password = ephemeral.random_password.windows.result
  })
  secret_string_wo_version = var.windows_password_version
}
