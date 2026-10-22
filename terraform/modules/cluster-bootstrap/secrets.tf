# Secrets reach Kubernetes only through External Secrets Operator (ESO), and
# each namespace gets its own SecretStore + IRSA role that can read ONLY its own
# secrets. No secret value ever passes through Terraform state.

# Grafana admin login: generated as an ephemeral value and written write-only.
resource "aws_secretsmanager_secret" "grafana_admin" {
  name                    = "${var.name}/grafana-admin"
  description             = "Grafana admin login (synced into monitoring by External Secrets)"
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = 7
}

ephemeral "random_password" "grafana_admin" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!#%*+-=?@_"
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id = aws_secretsmanager_secret.grafana_admin.id
  secret_string_wo = jsonencode({
    "admin-user"     = "admin"
    "admin-password" = ephemeral.random_password.grafana_admin.result
  })
  secret_string_wo_version = var.grafana_password_version
}

locals {
  ca_cert_parameter_arn = "arn:aws:ssm:${local.region}:${local.account_id}:parameter${var.ca_cert_parameter}"

  # namespace => what its SecretStore may read (and nothing else)
  eso_stores = {
    argocd     = { secrets = [var.argocd_deploy_key_secret_arn], parameters = [], only = "one secret only" }
    monitoring = { secrets = [aws_secretsmanager_secret.grafana_admin.arn], parameters = [], only = "one secret only" }
    # The load generator verifies the app's TLS certificate against the lab CA.
    # The CA certificate is public and lives only in SSM (String, no KMS).
    loadgen = { secrets = [], parameters = [local.ca_cert_parameter_arn], only = "one parameter only" }
  }
}

data "aws_iam_policy_document" "eso_store" {
  for_each = local.eso_stores

  dynamic "statement" {
    for_each = length(each.value.secrets) > 0 ? [1] : []
    content {
      sid       = "ReadOwnSecretOnly"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = each.value.secrets
    }
  }

  dynamic "statement" {
    for_each = length(each.value.secrets) > 0 ? [1] : []
    content {
      sid       = "DecryptViaSecretsManagerOnly"
      actions   = ["kms:Decrypt"]
      resources = [var.secrets_kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${local.region}.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = length(each.value.parameters) > 0 ? [1] : []
    content {
      sid       = "ReadOwnParameterOnly"
      actions   = ["ssm:GetParameter", "ssm:GetParameters"]
      resources = each.value.parameters
    }
  }
}

module "irsa_eso_store" {
  source   = "../irsa-role"
  for_each = local.eso_stores

  name              = "${var.name}-irsa-eso-${each.key}"
  description       = "External Secrets store in ${each.key} (${each.key}/eso-secretstore): ${each.value.only}"
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider     = var.oidc_provider
  namespace         = each.key
  service_account   = "eso-secretstore"
  policy_json       = data.aws_iam_policy_document.eso_store[each.key].json
}
