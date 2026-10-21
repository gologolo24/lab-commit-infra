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
  # namespace => secret ARN its SecretStore may read
  eso_stores = {
    argocd     = var.argocd_deploy_key_secret_arn
    monitoring = aws_secretsmanager_secret.grafana_admin.arn
  }
}

data "aws_iam_policy_document" "eso_store" {
  for_each = local.eso_stores

  statement {
    sid       = "ReadOwnSecretOnly"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [each.value]
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
}

module "irsa_eso_store" {
  source   = "../irsa-role"
  for_each = local.eso_stores

  name              = "${var.name}-irsa-eso-${each.key}"
  description       = "External Secrets store in ${each.key} (${each.key}/eso-secretstore): one secret only"
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider     = var.oidc_provider
  namespace         = each.key
  service_account   = "eso-secretstore"
  policy_json       = data.aws_iam_policy_document.eso_store[each.key].json
}
