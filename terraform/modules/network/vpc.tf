# VPC with exactly two private subnets and no public subnets.
#
# Internet egress (image pulls, GitHub) goes through a *Regional* NAT gateway.
# It needs an attached internet gateway, but no public subnet: no SUBNET's route
# table points at the IGW, so nothing in this VPC can be reached from the internet.
# (The only IGW route lives in the NAT gateway's own AWS-managed route table,
# which is associated with the NAT itself and can't be linked to subnets.)

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # required by Fargate, private endpoints and private hosted zones
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

# CIS: the default security group must allow nothing. Terraform adopts it and
# removes all its rules; every resource uses its own purpose-built group.
resource "aws_default_security_group" "locked" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-DO-NOT-USE" }
}

# The main route table stays empty (local route only). Both subnets are
# explicitly associated with the private route table below.
resource "aws_default_route_table" "unused" {
  default_route_table_id = aws_vpc.this.default_route_table_id

  tags = { Name = "${var.name}-main-unused" }
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
    # Lets the AWS Load Balancer Controller place *internal* ALBs here.
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Required by the Regional NAT gateway for egress. No subnet routes to it;
# AWS adds 0.0.0.0/0 -> IGW to the NAT's own managed route table automatically.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

# Regional NAT gateway: one gateway that spans the VPC's AZs automatically
# (auto mode), with no public subnet.
resource "aws_nat_gateway" "regional" {
  vpc_id            = aws_vpc.this.id
  availability_mode = "regional"

  tags = { Name = "${var.name}-regional" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-private" }
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.regional.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
