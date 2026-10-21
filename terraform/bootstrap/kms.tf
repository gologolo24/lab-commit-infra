# Customer-managed KMS keys, kept separate per purpose so access can be granted
# narrowly. The default key policy (account root) delegates access to IAM, so
# each role gets only the kms:Decrypt it needs, on only the key it needs.

# Encrypts Terraform state. State can contain sensitive values (resource
# attributes, generated passwords), so it gets its own key.
resource "aws_kms_key" "tfstate" {
  description             = "lab-commit: Terraform state bucket"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/lab-commit-tfstate"
  target_key_id = aws_kms_key.tfstate.key_id
}

# Encrypts application/pipeline secrets in Secrets Manager. Separate from the
# state key so that, for example, the CodeBuild role can decrypt its deploy key
# without being able to decrypt Terraform state.
resource "aws_kms_key" "secrets" {
  description             = "lab-commit: Secrets Manager secrets"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/lab-commit-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}
