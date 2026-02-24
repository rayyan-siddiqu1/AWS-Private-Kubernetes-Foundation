locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------------------------
# Security Groups (shells only — all rules managed as separate resources
# to avoid in-place replacement on rule changes)
# ---------------------------------------------------------------------------
resource "aws_security_group" "control_plane" {
  name        = "${var.project_name}-${var.environment}-control-plane-sg"
  description = "Security group for the Kubernetes control plane node"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-control-plane-sg"
    Role = "ControlPlane"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "worker" {
  name        = "${var.project_name}-${var.environment}-worker-sg"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-worker-sg"
    Role = "Worker"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ===========================================================================
# CONTROL PLANE — INGRESS RULES
# No 0.0.0.0/0 inbound; all rules scoped to admin IP or SG references.
# ===========================================================================

resource "aws_vpc_security_group_ingress_rule" "cp_ssh_from_admin" {
  security_group_id = aws_security_group.control_plane.id
  description       = "SSH access from admin IP only"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.my_ip

  tags = merge(local.common_tags, { Name = "cp-ssh-admin" })
}

resource "aws_vpc_security_group_ingress_rule" "cp_k8s_api_from_admin" {
  security_group_id = aws_security_group.control_plane.id
  description       = "Kubernetes API server access from admin IP"
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  cidr_ipv4         = var.my_ip

  tags = merge(local.common_tags, { Name = "cp-k8s-api-admin" })
}

resource "aws_vpc_security_group_ingress_rule" "cp_k8s_api_from_workers" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "Kubernetes API server access from worker nodes (kubelet to API server)"
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  referenced_security_group_id = aws_security_group.worker.id

  tags = merge(local.common_tags, { Name = "cp-k8s-api-workers" })
}

resource "aws_vpc_security_group_ingress_rule" "cp_etcd_from_workers" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "etcd client and peer ports - worker nodes only"
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2380
  referenced_security_group_id = aws_security_group.worker.id

  tags = merge(local.common_tags, { Name = "cp-etcd-workers" })
}

resource "aws_vpc_security_group_ingress_rule" "cp_etcd_self" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "etcd peer communication - self (supports future HA control plane)"
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2380
  referenced_security_group_id = aws_security_group.control_plane.id

  tags = merge(local.common_tags, { Name = "cp-etcd-self" })
}

resource "aws_vpc_security_group_ingress_rule" "cp_kubelet_from_workers" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "Kubelet API - worker nodes (used for logs, exec, port-forward)"
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  referenced_security_group_id = aws_security_group.worker.id

  tags = merge(local.common_tags, { Name = "cp-kubelet-workers" })
}

resource "aws_vpc_security_group_ingress_rule" "cp_controller_manager_self" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "Controller Manager health check - self only"
  ip_protocol                  = "tcp"
  from_port                    = 10257
  to_port                      = 10257
  referenced_security_group_id = aws_security_group.control_plane.id

  tags = merge(local.common_tags, { Name = "cp-controller-manager-self" })
}

resource "aws_vpc_security_group_ingress_rule" "cp_scheduler_self" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "Scheduler health check - self only"
  ip_protocol                  = "tcp"
  from_port                    = 10259
  to_port                      = 10259
  referenced_security_group_id = aws_security_group.control_plane.id

  tags = merge(local.common_tags, { Name = "cp-scheduler-self" })
}

resource "aws_vpc_security_group_ingress_rule" "cp_vxlan_from_workers" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "CNI VXLAN overlay (Flannel / Calico VXLAN) from worker nodes"
  ip_protocol                  = "udp"
  from_port                    = 8472
  to_port                      = 8472
  referenced_security_group_id = aws_security_group.worker.id

  tags = merge(local.common_tags, { Name = "cp-vxlan-workers" })
}

resource "aws_vpc_security_group_ingress_rule" "cp_bgp_from_workers" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "BGP for Calico from worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = 179
  to_port                      = 179
  referenced_security_group_id = aws_security_group.worker.id

  tags = merge(local.common_tags, { Name = "cp-bgp-workers" })
}

# ---------------------------------------------------------------------------
# Control Plane — Egress
# ---------------------------------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "cp_all_outbound" {
  security_group_id = aws_security_group.control_plane.id
  description       = "All outbound traffic (internet access via IGW)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, { Name = "cp-egress-all" })
}

# ===========================================================================
# WORKER NODES — INGRESS RULES
# Workers have no inbound path from the internet; all rules use SG references
# or the VPC CIDR for NodePort access.
# ===========================================================================

resource "aws_vpc_security_group_ingress_rule" "worker_all_from_control_plane" {
  security_group_id            = aws_security_group.worker.id
  description                  = "All traffic from the control plane (kubelet, CNI, etc.)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.control_plane.id

  tags = merge(local.common_tags, { Name = "worker-all-from-cp" })
}

resource "aws_vpc_security_group_ingress_rule" "worker_all_from_worker" {
  security_group_id            = aws_security_group.worker.id
  description                  = "All traffic between worker nodes (pod networking, CNI)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.worker.id

  tags = merge(local.common_tags, { Name = "worker-all-from-worker" })
}

resource "aws_vpc_security_group_ingress_rule" "worker_nodeport_internal" {
  security_group_id = aws_security_group.worker.id
  description       = "NodePort range accessible within VPC CIDR only (no internet exposure)"
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
  cidr_ipv4         = var.vpc_cidr_block

  tags = merge(local.common_tags, { Name = "worker-nodeport-internal" })
}

resource "aws_vpc_security_group_ingress_rule" "worker_ssh_from_control_plane" {
  security_group_id            = aws_security_group.worker.id
  description                  = "SSH access from control plane only (no direct public SSH)"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.control_plane.id

  tags = merge(local.common_tags, { Name = "worker-ssh-from-cp" })
}

# ---------------------------------------------------------------------------
# Worker Nodes — Egress
# Traffic leaves via NAT Gateway; no public IP on workers.
# ---------------------------------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "worker_all_outbound" {
  security_group_id = aws_security_group.worker.id
  description       = "All outbound traffic (egress via NAT Gateway in public subnet)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, { Name = "worker-egress-all" })
}
