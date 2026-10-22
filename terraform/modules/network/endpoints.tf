# VPC endpoints keep AWS API traffic on the AWS network instead of going
# through the NAT gateway.

# Gateway endpoint for S3 (free). ECR stores image layers in S3, so Fargate
# image pulls use it too.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.name}-s3" }
}

# Interface endpoints, one ENI per subnet. Private DNS makes the normal
# service hostnames (for example sts.us-west-2.amazonaws.com) resolve to them.
resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.this["vpce"].id]

  tags = { Name = "${var.name}-${each.value}" }
}
