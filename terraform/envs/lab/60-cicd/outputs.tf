output "ecr_repository_urls" {
  value = module.cicd.ecr_repository_urls
}

output "pipeline_names" {
  value = module.cicd.pipeline_names
}

output "github_connection_arn" {
  value = module.cicd.github_connection_arn
}

output "github_connection_status" {
  value = module.cicd.github_connection_status
}

output "artifacts_bucket" {
  value = module.cicd.artifacts_bucket
}
