# IRSA roles for the cluster add-ons that call AWS. Each role can be assumed by
# exactly one service account. Roles for apps and External Secrets are created in
# the stacks that own those secrets/resources.

# AWS Load Balancer Controller: the official policy of the pinned release. It's
# tag-scoped: it may only modify load balancers/SGs tagged for this cluster.
module "irsa_aws_load_balancer_controller" {
  source = "../irsa-role"

  name              = "${var.name}-irsa-aws-load-balancer-controller"
  description       = "AWS Load Balancer Controller v3.6.0 (kube-system/aws-load-balancer-controller)"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "kube-system"
  service_account   = "aws-load-balancer-controller"
  policy_json       = file("${path.module}/policies/aws-load-balancer-controller-v3.6.0.json")
}

# external-dns: may change records in ONE private hosted zone, nothing else.
data "aws_iam_policy_document" "external_dns" {
  statement {
    sid       = "ChangeRecordsInLabZoneOnly"
    actions   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets", "route53:ListTagsForResources"]
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}"]
  }

  # Needed to find the zone by name; these actions don't support resource scoping.
  statement {
    sid       = "DiscoverZones"
    actions   = ["route53:ListHostedZones", "route53:GetChange"]
    resources = ["*"]
  }
}

module "irsa_external_dns" {
  source = "../irsa-role"

  name              = "${var.name}-irsa-external-dns"
  description       = "external-dns (kube-system/external-dns): records in the private lab zone only"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "kube-system"
  service_account   = "external-dns"
  policy_json       = data.aws_iam_policy_document.external_dns.json
}
