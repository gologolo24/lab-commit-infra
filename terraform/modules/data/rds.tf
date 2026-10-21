# RDS PostgreSQL (PDF: "Create RDS MySQL/PostgreSQL"; the backend runs a SELECT on it).
#
# Private, encrypted, TLS-only. The master password is generated and kept by RDS
# in Secrets Manager (never in Terraform state). The app logs in as a read-only
# user with short-lived IAM tokens, so the app has no password at all.

resource "aws_kms_key" "rds" {
  description             = "${var.name}: RDS storage, snapshots and backups"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_db_subnet_group" "this" {
  name        = var.name
  description = "${var.name}: private subnets only"
  subnet_ids  = var.subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-postgres${split(".", var.engine_version)[0]}"
  family      = "postgres${split(".", var.engine_version)[0]}"
  description = "${var.name}: TLS required, connection logging"

  parameter {
    name  = "rds.force_ssl" # refuse plain-text connections
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }
}

# Created up front so the logs are KMS-encrypted and expire (RDS would create
# an unencrypted group that never expires).
resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/instance/${var.name}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

# Accepted for the lab: deletion protection off and no final snapshot
# (AWS-0177) so the environment can be torn down in one go; production: on.
#trivy:ignore:AVD-AWS-0177
resource "aws_db_instance" "this" {
  identifier = var.name

  engine                     = "postgres"
  engine_version             = var.engine_version
  auto_minor_version_upgrade = true
  instance_class             = var.instance_class
  multi_az                   = var.multi_az

  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  db_name                       = var.db_name
  username                      = var.master_username
  manage_master_user_password   = true # RDS generates + rotates it in Secrets Manager
  master_user_secret_kms_key_id = var.secrets_kms_key_arn

  iam_database_authentication_enabled = true # app logs in with IAM tokens, no password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  port                   = 5432
  parameter_group_name   = aws_db_parameter_group.this.name
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Performance Insights: free with 7-day retention, encrypted with the RDS key.
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = aws_kms_key.rds.arn

  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-03:30"
  maintenance_window      = "sun:04:00-sun:04:30"
  copy_tags_to_snapshot   = true

  deletion_protection = false # lab only
  skip_final_snapshot = true  # lab only
  apply_immediately   = true

  depends_on = [aws_cloudwatch_log_group.postgresql]
}
