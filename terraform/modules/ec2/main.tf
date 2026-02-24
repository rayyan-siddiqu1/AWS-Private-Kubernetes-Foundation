locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------------------------
# Data Source — Latest Ubuntu 24.04 LTS (Noble Numbat) AMI
# Owner: 099720109477 = Canonical's official AWS account
#
# The name glob uses "hvm-ssd*" (with wildcard) because Canonical publishes
# Ubuntu 24.04 AMIs under two storage paths depending on region:
#   - older/global:  ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*
#   - newer regions: ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*
# The wildcard matches both, ensuring the data source resolves in all regions.
# ---------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ---------------------------------------------------------------------------
# Control Plane EC2 Instance
#
# Placement: public subnet (receives auto-assigned public IP from subnet setting)
# IMDSv2:    enforced (http_tokens = "required")
# Monitoring: detailed monitoring enabled
# Storage:   40GB gp3 root volume, encrypted
# IAM:       instance profile attached for SSM + minimal EC2 permissions
# ---------------------------------------------------------------------------
resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_control_plane
  subnet_id                   = var.public_subnet_id
  associate_public_ip_address = true
  key_name                    = var.key_name
  iam_instance_profile        = var.instance_profile_name

  vpc_security_group_ids = [var.control_plane_sg_id]

  # Detailed monitoring — 1-minute metric granularity
  monitoring = true

  # Enforce IMDSv2 — prevents SSRF-based metadata credential theft
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.control_plane_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(local.common_tags, {
      Name = "${var.project_name}-${var.environment}-control-plane-root-vol"
      Role = "ControlPlane"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-control-plane"
    Role = "ControlPlane"
  })

  # Prevent AMI changes from forcing instance replacement on subsequent plans
  lifecycle {
    ignore_changes = [ami]
  }
}

# ---------------------------------------------------------------------------
# Worker Node EC2 Instances (2 nodes)
#
# Placement: private subnet (no public IP — internet access via NAT Gateway)
# IMDSv2:    enforced
# Monitoring: detailed monitoring enabled
# Storage:   60GB gp3 root volume, encrypted
# IAM:       same instance profile as control plane
# ---------------------------------------------------------------------------
resource "aws_instance" "worker" {
  count = 2

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_worker
  subnet_id                   = var.private_subnet_id
  associate_public_ip_address = false
  key_name                    = var.key_name
  iam_instance_profile        = var.instance_profile_name

  vpc_security_group_ids = [var.worker_sg_id]

  monitoring = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.worker_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(local.common_tags, {
      Name = "${var.project_name}-${var.environment}-worker-${count.index + 1}-root-vol"
      Role = "Worker"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-worker-${count.index + 1}"
    Role = "Worker"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}
