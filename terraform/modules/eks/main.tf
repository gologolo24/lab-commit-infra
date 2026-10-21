# EKS on Fargate only (PDF: "Node Groups are NOT ALLOWED", "Only Private Subnets").
#
# Built on the community module terraform-aws-modules/eks (pinned). It always sets
# bootstrap_self_managed_addons = false, so EKS installs none of its default
# DaemonSets (vpc-cni, kube-proxy). They can't run on Fargate anyway: Fargate
# brings its own networking into every pod's VM.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Private API endpoint only: reachable from inside the VPC (ops instance), never from the internet.
  endpoint_private_access = true
  endpoint_public_access  = false

  # Access entries only (no aws-auth ConfigMap). Exactly one admin: the MFA-protected role.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    admin = {
      principal_arn = var.admin_role_arn
      policy_associations = {
        cluster_admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Kubernetes Secrets are envelope-encrypted with a customer-managed KMS key.
  create_kms_key                  = true
  enable_kms_key_rotation         = true
  kms_key_deletion_window_in_days = 7
  kms_key_administrators          = [var.admin_role_arn]
  encryption_config               = { resources = ["secrets"] }

  # Control-plane logs (audit trail of every API call), encrypted, 30 days.
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_kms_key_id        = var.logs_kms_key_arn
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  # No nodes, so no node security group.
  create_node_security_group = false

  # The control plane's security group: HTTPS only from the ops instance (SSM tunnel).
  # Fargate pods use the EKS-managed *primary* cluster security group (output below).
  security_group_additional_rules = {
    ops_https = {
      type                     = "ingress"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      source_security_group_id = var.ops_security_group_id
      description              = "kubectl / Terraform from the ops instance (SSM tunnel)"
    }
  }

  # Stay on standard support: no surprise extended-support charges.
  upgrade_policy      = { support_type = "STANDARD" }
  deletion_protection = false # lab: allow teardown

  # IAM OIDC provider for IRSA.
  enable_irsa = true

  # Every pod runs on Fargate, in the private subnets. The pod execution role
  # gets only AmazonEKSFargatePodExecutionRolePolicy (image pulls). The CNI policy
  # is for the aws-node DaemonSet on EC2 nodes, so it's turned off here.
  fargate_profiles = {
    for profile, namespaces in var.fargate_profiles : profile => {
      name                       = "${var.name}-${profile}"
      selectors                  = [for ns in namespaces : { namespace = ns }]
      iam_role_attach_cni_policy = false
    }
  }

  # Managed add-ons, pinned. Created after the Fargate profiles exist.
  addons = {
    coredns = {
      addon_version        = var.addon_versions.coredns
      most_recent          = false
      configuration_values = jsonencode({ computeType = "Fargate" })
    }
    metrics-server = {
      # The EKS add-on listens on 10251, so it doesn't clash with the Fargate kubelet on 10250.
      addon_version = var.addon_versions.metrics_server
      most_recent   = false
    }
  }
}
