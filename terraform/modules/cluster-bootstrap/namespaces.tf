# Namespaces Terraform owns (the rest are created by Argo CD). Pod Security
# Admission: baseline is enforced, restricted is reported as a warning.

resource "kubernetes_namespace_v1" "platform" {
  for_each = toset(["external-secrets", "argocd"])

  metadata {
    name = each.key
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}
