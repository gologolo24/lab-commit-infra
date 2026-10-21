# lab / 10-network: VPC, 2 private subnets, Regional NAT, endpoints, flow logs,
# private DNS zone, security groups. All logic lives in modules/network.
#
# Run with: scripts/tf.sh lab 10-network plan

locals {
  env = yamldecode(file("${path.module}/../env.yaml"))
}

module "network" {
  source = "../../../modules/network"

  name            = local.env.name
  vpc_cidr        = local.env.network.vpc_cidr
  private_subnets = local.env.network.private_subnets
  zone_name       = local.env.dns.zone_name
  app_hostname    = local.env.dns.app_hostname
}
