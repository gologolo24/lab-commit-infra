# Reusable module: no provider configuration and no backend here. The caller
# configures the helm/kubernetes providers (through the SSM tunnel to the
# private EKS endpoint).
terraform {
  required_version = ">= 1.11" # write-only arguments (secret_string_wo)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.69"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7" # ephemeral random_password
    }
  }
}

data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region
}
