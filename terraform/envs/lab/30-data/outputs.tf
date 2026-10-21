# Read by later stacks through terraform_remote_state (envs/<env>/30-data/terraform.tfstate).

output "db_address" {
  value = module.data.db_address
}

output "db_port" {
  value = module.data.db_port
}

output "db_name" {
  value = module.data.db_name
}

output "db_resource_id" {
  value = module.data.db_resource_id
}

output "master_username" {
  value = module.data.master_username
}

output "master_secret_arn" {
  value = module.data.master_secret_arn
}

output "app_user" {
  value = module.data.app_user
}

output "kms_key_arn" {
  value = module.data.kms_key_arn
}

output "irsa_role_arns" {
  value = module.data.irsa_role_arns
}
