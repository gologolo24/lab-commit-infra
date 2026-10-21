# Who in the cluster may use the database, and how (IRSA, one service account each).

# backend: connect as the read-only app user with an IAM token. Nothing else:
# no secrets, no other DB users.
data "aws_iam_policy_document" "backend" {
  statement {
    sid       = "ConnectAsReadOnlyAppUser"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${local.region}:${local.account_id}:dbuser:${aws_db_instance.this.resource_id}/${var.app_user}"]
  }
}

module "irsa_backend" {
  source = "../irsa-role"

  name              = "${var.name}-irsa-backend"
  description       = "backend (${var.app_namespace}/backend): rds-db:connect as ${var.app_user} only"
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider     = var.oidc_provider
  namespace         = var.app_namespace
  service_account   = "backend"
  policy_json       = data.aws_iam_policy_document.backend.json
}

# db-migrate job: reads the master password once to create the table, the seed
# value and the read-only app user. Only this secret, decrypted only via Secrets Manager.
data "aws_iam_policy_document" "db_migrator" {
  statement {
    sid       = "ReadMasterSecretOnly"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_db_instance.this.master_user_secret[0].secret_arn]
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

module "irsa_db_migrator" {
  source = "../irsa-role"

  name              = "${var.name}-irsa-db-migrator"
  description       = "db-migrate job (${var.app_namespace}/db-migrator): read the RDS master secret only"
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider     = var.oidc_provider
  namespace         = var.app_namespace
  service_account   = "db-migrator"
  policy_json       = data.aws_iam_policy_document.db_migrator.json
}
