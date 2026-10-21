# Configures the Windows client through SSM State Manager (not user data: user
# data is readable from instance metadata and must never carry secrets).
# Runs as soon as the SSM agent registers, then daily (idempotent), so a new
# CA certificate or a rotated password is picked up automatically.

resource "aws_ssm_document" "windows_setup" {
  name            = "${var.name}-windows-setup"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.module}/files/windows-setup.yaml")
}

resource "aws_ssm_association" "windows_setup" {
  association_name    = "${var.name}-windows-setup"
  name                = aws_ssm_document.windows_setup.name
  schedule_expression = "rate(1 day)"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.this["windows"].id]
  }

  parameters = {
    Region      = local.region
    SecretId    = aws_secretsmanager_secret.windows.name
    CaParameter = var.ca_cert_parameter
    StartUrls   = join(",", var.chrome_start_urls)
  }

  depends_on = [aws_secretsmanager_secret_version.windows]
}
