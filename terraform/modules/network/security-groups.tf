# Security groups (PDF: "configure limited SG's Ports Opened").
#
# Rules only. A group created by Terraform starts with no egress (Terraform
# removes AWS's default allow-all egress rule). Every allowed flow is listed
# below, each one port from one source or to one destination.
#
# Groups that involve the EKS cluster security group (which doesn't exist
# yet) get their extra rules in the 20-eks stack.

locals {
  security_groups = {
    "alb"          = "Internal ALB: HTTPS 443 only from the Windows client, load generator pods and CodeBuild"
    "windows"      = "Windows test client: no inbound; outbound HTTPS only"
    "ops"          = "Ops instance (EKS API tunnel): no inbound; outbound HTTPS inside the VPC only"
    "rds"          = "RDS PostgreSQL: 5432 only from backend pods"
    "backend-pods" = "Backend pods (SecurityGroupPolicy): may reach RDS on 5432"
    "loadgen-pods" = "Load generator pods (SecurityGroupPolicy): may reach the ALB on 443"
    "codebuild"    = "CodeBuild in the VPC: outbound HTTPS and SSH (GitHub) only"
    "vpce"         = "Interface VPC endpoints: HTTPS 443 from inside the VPC"
  }

  # Ingress: one port, one source security group.
  ingress_from_sg = {
    alb_from_windows   = { sg = "alb", port = 443, from = "windows", desc = "HTTPS from the Windows test client (Chrome)" }
    alb_from_loadgen   = { sg = "alb", port = 443, from = "loadgen-pods", desc = "HTTPS from the load generator pods" }
    alb_from_codebuild = { sg = "alb", port = 443, from = "codebuild", desc = "HTTPS smoke test from the pipeline" }
    rds_from_backend   = { sg = "rds", port = 5432, from = "backend-pods", desc = "PostgreSQL from backend pods only" }
  }

  # Egress that stays inside the VPC (to a security group or to the VPC range).
  egress_internal = merge(
    { for p in var.alb_target_ports : "alb_to_targets_${p}" => {
      sg = "alb", port = p, to_sg = null, to_cidr = var.vpc_cidr, desc = "ALB to pod targets on ${p}"
    } },
    {
      ops_to_vpc     = { sg = "ops", port = 443, to_sg = null, to_cidr = var.vpc_cidr, desc = "EKS private API endpoint and VPC endpoints" }
      backend_to_rds = { sg = "backend-pods", port = 5432, to_sg = "rds", to_cidr = null, desc = "PostgreSQL to RDS" }
      loadgen_to_alb = { sg = "loadgen-pods", port = 443, to_sg = "alb", to_cidr = null, desc = "HTTPS load to the app through the ALB" }
    },
  )

  # Egress to the internet (through the NAT gateway), only where unavoidable.
  egress_internet = {
    windows_https   = { sg = "windows", port = 443, desc = "HTTPS: the ALB, VPC endpoints, Chrome download" }
    codebuild_https = { sg = "codebuild", port = 443, desc = "Docker base images, PyPI, GitHub HTTPS" }
    codebuild_ssh   = { sg = "codebuild", port = 22, desc = "git push to the GitOps repo with its deploy key (GitHub SSH)" }
  }
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  name        = "${var.name}-${each.key}"
  description = each.value
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-${each.key}" }
}

resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  for_each = local.ingress_from_sg

  security_group_id            = aws_security_group.this[each.value.sg].id
  referenced_security_group_id = aws_security_group.this[each.value.from].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.value.desc

  tags = { Name = each.key }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_vpc" {
  security_group_id = aws_security_group.this["vpce"].id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to AWS APIs from anything inside the VPC"

  tags = { Name = "vpce_from_vpc" }
}

resource "aws_vpc_security_group_egress_rule" "internal" {
  for_each = local.egress_internal

  security_group_id            = aws_security_group.this[each.value.sg].id
  referenced_security_group_id = each.value.to_sg == null ? null : aws_security_group.this[each.value.to_sg].id
  cidr_ipv4                    = each.value.to_cidr
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.value.desc

  tags = { Name = each.key }
}

# Accepted (AWS-0104): these two clients need the internet on one port each,
# through the NAT gateway. Nothing can connect *in* (no inbound rules, no public IPs).
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "internet" {
  for_each = local.egress_internet

  security_group_id = aws_security_group.this[each.value.sg].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = each.value.desc

  tags = { Name = each.key }
}
