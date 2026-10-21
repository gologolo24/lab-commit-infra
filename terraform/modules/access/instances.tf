# Two private instances. No key pair, no public IP, no inbound rules: the only
# way in is AWS Systems Manager (Session Manager / Fleet Manager).

data "aws_ssm_parameter" "windows_ami" {
  name = var.windows_ami_parameter
}

data "aws_ssm_parameter" "ops_ami" {
  name = var.ops_ami_parameter
}

locals {
  instances = {
    windows = {
      ami           = data.aws_ssm_parameter.windows_ami.value
      instance_type = var.windows_instance_type
      sg            = var.windows_security_group_id
      disk_gb       = 50 # Windows Server needs at least 30 GB
      purpose       = "Windows test client: Chrome to the private app URL (PDF)"
    }
    ops = {
      ami           = data.aws_ssm_parameter.ops_ami.value
      instance_type = var.ops_instance_type
      sg            = var.ops_security_group_id
      disk_gb       = 8
      purpose       = "SSM port-forwarding hop to the private EKS API endpoint"
    }
  }
}

resource "aws_instance" "this" {
  for_each = local.instances

  ami                         = each.value.ami
  instance_type               = each.value.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [each.value.sg]
  iam_instance_profile        = aws_iam_instance_profile.instance[each.key].name
  associate_public_ip_address = false # and no key_name: PDF "no key-pair is allowed"

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = each.value.disk_gb
    encrypted   = true
    kms_key_id  = aws_kms_key.ebs.arn
  }

  tags = {
    Name    = "${var.name}-${each.key}"
    Purpose = each.value.purpose
  }

  # A newer AMI must not replace a running instance; rebuild on purpose instead.
  lifecycle {
    ignore_changes = [ami]
  }
}
