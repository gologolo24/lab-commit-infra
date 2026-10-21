# Read by later stacks through terraform_remote_state (envs/<env>/10-network/terraform.tfstate).

output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_cidr" {
  value = module.network.vpc_cidr
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "private_route_table_id" {
  value = module.network.private_route_table_id
}

output "nat_gateway_id" {
  value = module.network.nat_gateway_id
}

output "security_group_ids" {
  value = module.network.security_group_ids
}

output "zone_id" {
  value = module.network.zone_id
}

output "zone_name" {
  value = module.network.zone_name
}

output "app_fqdn" {
  value = module.network.app_fqdn
}

output "app_certificate_arn" {
  value = module.network.app_certificate_arn
}

output "logs_kms_key_arn" {
  value = module.network.logs_kms_key_arn
}
