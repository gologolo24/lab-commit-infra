# Private hosted zone: names resolve only inside this VPC (PDF: "your service
# shouldn't be accessible publicly"). Records such as lab-commit-task.<zone>
# are created later by external-dns from the Ingress hosts.
resource "aws_route53_zone" "private" {
  name    = var.zone_name
  comment = "${var.name}: private zone, resolvable only inside ${var.name} VPC"

  vpc {
    vpc_id = aws_vpc.this.id
  }
}

# The TLS certificate (self-signed CA + server cert) is created and imported
# into ACM by scripts/create-tls-cert.sh, so its private key never enters
# Terraform state. Terraform only looks it up. Run the script before this stack.
data "aws_acm_certificate" "app" {
  domain      = "${var.app_hostname}.${var.zone_name}"
  types       = ["IMPORTED"]
  statuses    = ["ISSUED"]
  most_recent = true
}
