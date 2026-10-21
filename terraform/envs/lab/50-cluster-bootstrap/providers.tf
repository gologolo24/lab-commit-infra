terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Partial config: scripts/tf.sh passes ../backend.hcl plus
  # key = envs/<env>/<stack>/terraform.tfstate (derived from the folder).
  backend "s3" {}
}

# Credentials come from the environment (AWS_PROFILE, set by scripts/tf.sh).
provider "aws" {
  region              = local.env.region
  allowed_account_ids = [local.env.account_id]

  default_tags {
    tags = local.tags
  }
}

# The EKS API endpoint is private. scripts/eks-tunnel.sh forwards it to
# 127.0.0.1:<api_tunnel_port> through the ops instance (SSM); TLS is still
# verified against the real endpoint name (tls_server_name) and the cluster CA.
# Authentication: a short-lived token from `aws eks get-token` (lab-commit-admin role).
locals {
  kube = {
    host                   = "https://127.0.0.1:${local.env.cluster_bootstrap.api_tunnel_port}"
    tls_server_name        = trimprefix(local.eks.cluster_endpoint, "https://")
    cluster_ca_certificate = base64decode(local.eks.cluster_certificate_authority_data)
    exec_args              = ["eks", "get-token", "--cluster-name", local.eks.cluster_name, "--region", local.env.region, "--output", "json"]
  }
}

provider "kubernetes" {
  host                   = local.kube.host
  tls_server_name        = local.kube.tls_server_name
  cluster_ca_certificate = local.kube.cluster_ca_certificate

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.kube.exec_args
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.kube.host
    tls_server_name        = local.kube.tls_server_name
    cluster_ca_certificate = local.kube.cluster_ca_certificate

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.kube.exec_args
    }
  }
}
