locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------------------------
# Trust Policy — allows EC2 service to assume this role
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "EC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# IAM Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "k8s_node" {
  name               = "${var.project_name}-${var.environment}-k8s-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for Kubernetes nodes. Grants SSM access and minimal EC2 read permissions."

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-k8s-node-role"
  })
}

# ---------------------------------------------------------------------------
# Managed Policy Attachment — SSM Session Manager (replaces bastion host need)
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.k8s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---------------------------------------------------------------------------
# Custom Inline Policy — minimal EC2 describe permissions for node operations
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "k8s_node_minimal" {
  statement {
    sid    = "EC2DescribeForNodeDiscovery"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "k8s_node_minimal" {
  name        = "${var.project_name}-${var.environment}-k8s-node-minimal"
  description = "Minimal EC2 read permissions required for Kubernetes node operations"
  policy      = data.aws_iam_policy_document.k8s_node_minimal.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-k8s-node-minimal"
  })
}

resource "aws_iam_role_policy_attachment" "k8s_node_minimal" {
  role       = aws_iam_role.k8s_node.name
  policy_arn = aws_iam_policy.k8s_node_minimal.arn
}

# ---------------------------------------------------------------------------
# Instance Profile — attached to all EC2 nodes
# ---------------------------------------------------------------------------
resource "aws_iam_instance_profile" "k8s_node" {
  name = "${var.project_name}-${var.environment}-k8s-node-profile"
  role = aws_iam_role.k8s_node.name

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-k8s-node-profile"
  })
}
