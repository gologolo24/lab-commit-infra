output "ecr_repository_urls" {
  description = "Image repositories, per service (image.repository in the GitOps values)."
  value       = { for s, r in aws_ecr_repository.this : s => r.repository_url }
}

output "pipeline_names" {
  value = { for s, p in aws_codepipeline.this : s => p.name }
}

output "github_connection_arn" {
  value = aws_codeconnections_connection.github.arn
}

output "github_connection_status" {
  description = "PENDING until the one-time handshake in the console; then AVAILABLE."
  value       = aws_codeconnections_connection.github.connection_status
}

output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}
