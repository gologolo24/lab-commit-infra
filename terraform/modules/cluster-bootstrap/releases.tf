# Cluster add-ons that must exist before GitOps can work, in dependency order:
#   External Secrets -> Argo CD repo credentials -> Load Balancer Controller +
#   external-dns -> Argo CD -> (argocd-apps.tf) projects + ApplicationSets.
# Everything else (monitoring, KEDA, apps) is deployed by Argo CD from Git.
#
# Fargate notes: every pod needs resource requests (Fargate sizes the pod from
# them); nothing may listen on 10250 (the Fargate kubelet's port); pods have no
# IMDS, so region/VPC are passed explicitly.

locals {
  argocd_fqdn = "${var.argocd_hostname}.${var.zone_name}"

  small = {
    requests = { cpu = "50m", memory = "64Mi" }
    limits   = { memory = "128Mi" }
  }
  medium = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { memory = "256Mi" }
  }

  # Shared by every Ingress on the one internal ALB (group "<name>").
  alb_ingress_annotations = {
    "alb.ingress.kubernetes.io/scheme"                              = "internal"
    "alb.ingress.kubernetes.io/target-type"                         = "ip" # Fargate: IP targets only
    "alb.ingress.kubernetes.io/group.name"                          = var.name
    "alb.ingress.kubernetes.io/listen-ports"                        = jsonencode([{ HTTPS = 443 }]) # HTTPS only
    "alb.ingress.kubernetes.io/certificate-arn"                     = var.certificate_arn
    "alb.ingress.kubernetes.io/ssl-policy"                          = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
    "alb.ingress.kubernetes.io/security-groups"                     = var.alb_security_group_id
    "alb.ingress.kubernetes.io/manage-backend-security-group-rules" = "true"
    "alb.ingress.kubernetes.io/load-balancer-attributes"            = "routing.http.drop_invalid_header_fields.enabled=true"
  }
}

# --- 1. External Secrets Operator ------------------------------------------
resource "helm_release" "external_secrets" {
  name        = "external-secrets"
  namespace   = kubernetes_namespace_v1.platform["external-secrets"].metadata[0].name
  repository  = "https://charts.external-secrets.io"
  chart       = "external-secrets"
  version     = var.chart_versions.external_secrets
  wait        = true
  timeout     = 900
  max_history = 5

  values = [yamlencode({
    installCRDs    = true
    resources      = local.medium
    webhook        = { port = 9443, resources = local.small } # not 10250: the Fargate kubelet uses it
    certController = { resources = local.small }
  })]
}

# --- 2. Argo CD's Git credentials, via External Secrets ----------------------
resource "helm_release" "argocd_repo_secret" {
  name        = "argocd-repo-secret"
  namespace   = kubernetes_namespace_v1.platform["argocd"].metadata[0].name
  chart       = "${path.module}/charts/argocd-repo-secret"
  wait        = true
  max_history = 5

  values = [yamlencode({
    region          = local.region
    roleArn         = module.irsa_eso_store["argocd"].arn
    deployKeySecret = var.argocd_deploy_key_secret_arn
    repoUrl         = var.gitops_repo_url
  })]

  depends_on = [helm_release.external_secrets] # needs the ESO CRDs
}

# --- 3. AWS Load Balancer Controller (PDF: "Implement load Balancer Controller") ---
resource "helm_release" "aws_load_balancer_controller" {
  name        = "aws-load-balancer-controller"
  namespace   = "kube-system"
  repository  = "https://aws.github.io/eks-charts"
  chart       = "aws-load-balancer-controller"
  version     = var.chart_versions.aws_load_balancer_controller
  wait        = true
  timeout     = 900
  max_history = 5

  values = [yamlencode({
    clusterName  = var.name
    region       = local.region # no IMDS on Fargate
    vpcId        = var.vpc_id
    replicaCount = 2
    resources    = local.medium
    serviceAccount = {
      name        = "aws-load-balancer-controller"
      annotations = { "eks.amazonaws.com/role-arn" = var.irsa_role_arns["aws_load_balancer_controller"] }
    }
    # Only Ingress is used; don't mutate every Service of type LoadBalancer.
    enableServiceMutatorWebhook = false
    defaultTags                 = merge(var.tags, { ManagedBy = "aws-load-balancer-controller" })
  })]
}

# --- 4. external-dns: Ingress hosts -> records in the private zone -------------
resource "helm_release" "external_dns" {
  name        = "external-dns"
  namespace   = "kube-system"
  repository  = "https://kubernetes-sigs.github.io/external-dns/"
  chart       = "external-dns"
  version     = var.chart_versions.external_dns
  wait        = true
  timeout     = 900
  max_history = 5

  values = [yamlencode({
    provider      = { name = "aws" }
    env           = [{ name = "AWS_DEFAULT_REGION", value = local.region }] # no IMDS on Fargate
    sources       = ["ingress"]
    domainFilters = [var.zone_name]
    policy        = "sync" # also deletes the records it created (clean teardown)
    registry      = "txt"
    txtOwnerId    = var.name # never touches records it doesn't own
    extraArgs     = ["--aws-zone-type=private", "--zone-id-filter=${var.zone_id}"]
    resources     = local.small
    serviceAccount = {
      name        = "external-dns"
      annotations = { "eks.amazonaws.com/role-arn" = var.irsa_role_arns["external_dns"] }
    }
  })]
}

# --- 5. Argo CD (PDF: "Deploy any CD tool on the cluster") -----------------------
resource "helm_release" "argo_cd" {
  name        = "argo-cd"
  namespace   = kubernetes_namespace_v1.platform["argocd"].metadata[0].name
  repository  = "https://argoproj.github.io/argo-helm"
  chart       = "argo-cd"
  version     = var.chart_versions.argo_cd
  wait        = true
  timeout     = 900
  max_history = 5

  values = [yamlencode({
    global = { domain = local.argocd_fqdn }
    configs = {
      params = { "server.insecure" = true } # TLS ends at the ALB
      cm = {
        "timeout.reconciliation" = "60s"
        "accounts.reviewer"      = "login" # UI login only, no API keys
      }
      # Reviewers see everything and may only start the load test. Everyone
      # else without a role gets nothing (policy.default is empty).
      rbac = {
        "policy.csv" = <<-EOT
          p, role:reviewer, applications, sync, apps/lab-loadgen, allow
          p, role:reviewer, logs, get, */*, allow
          g, role:reviewer, role:readonly
          g, reviewer, role:reviewer
        EOT
      }
      # The in-cluster cluster gets an "env" label: the ApplicationSets select on it.
      # A new environment = a new cluster secret with its own env label.
      clusterCredentials = {
        in-cluster = {
          server = "https://kubernetes.default.svc"
          labels = { env = var.environment }
          config = { tlsClientConfig = { insecure = false } }
        }
      }
    }
    dex             = { enabled = false } # local admin only (lab)
    notifications   = { enabled = false }
    controller      = { resources = { requests = { cpu = "250m", memory = "512Mi" }, limits = { memory = "1Gi" } } }
    repoServer      = { resources = { requests = { cpu = "100m", memory = "256Mi" }, limits = { memory = "512Mi" } } }
    applicationSet  = { resources = local.medium }
    redis           = { resources = local.medium }
    redisSecretInit = { resources = local.small }
    server = {
      resources = local.medium
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        hostname         = local.argocd_fqdn
        annotations = merge(local.alb_ingress_annotations, {
          "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
        })
      }
    }
  })]

  depends_on = [
    helm_release.argocd_repo_secret,           # Git credentials exist before Argo CD starts
    helm_release.aws_load_balancer_controller, # its webhook validates the Ingress
  ]
}
