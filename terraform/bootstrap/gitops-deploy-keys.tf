# Secret *containers* for the GitOps repository's SSH deploy keys.
#
#   argocd    - read-only: Argo CD pulls manifests
#   codebuild - read/write: the pipeline commits new image tags
#
# Terraform only creates the empty, KMS-encrypted secrets, so later stacks can
# grant each consumer access to its own secret ARN. The key pairs are created
# and uploaded by scripts/create-gitops-deploy-keys.sh, so private key material
# never appears in Terraform state, plan output or Git.

locals {
  gitops_deploy_keys = {
    argocd    = "argocd (read-only)"
    codebuild = "codebuild pipeline (write: image tags)"
  }
}

resource "aws_secretsmanager_secret" "gitops_deploy_key" {
  for_each = local.gitops_deploy_keys

  name                    = "lab-commit/gitops-deploy-key/${each.key}"
  description             = "SSH private key for ${var.github_owner}/${var.gitops_repo}: ${each.value}. Value set by scripts/create-gitops-deploy-keys.sh."
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 7
}
