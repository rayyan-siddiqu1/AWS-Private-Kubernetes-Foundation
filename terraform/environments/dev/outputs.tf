# ---------------------------------------------------------------------------
# Control Plane
# ---------------------------------------------------------------------------
output "control_plane_public_ip" {
  description = "Public IP address of the Kubernetes control plane node — use this to reach the API server and SSH"
  value       = module.ec2.control_plane_public_ip
}

output "control_plane_private_ip" {
  description = "Private IP address of the Kubernetes control plane node — used for internal cluster communication"
  value       = module.ec2.control_plane_private_ip
}

output "control_plane_instance_id" {
  description = "EC2 instance ID of the control plane node"
  value       = module.ec2.control_plane_instance_id
}

output "control_plane_ssh_command" {
  description = "SSH command to connect to the control plane (replace key path as needed)"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${module.ec2.control_plane_public_ip}"
}

# ---------------------------------------------------------------------------
# Worker Nodes
# ---------------------------------------------------------------------------
output "worker_private_ips" {
  description = "Private IP addresses of the Kubernetes worker nodes"
  value       = module.ec2.worker_private_ips
}

output "worker_instance_ids" {
  description = "EC2 instance IDs of the Kubernetes worker nodes"
  value       = module.ec2.worker_instance_ids
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet (control plane + NAT Gateway)"
  value       = module.vpc.public_subnet_id
}

output "private_subnet_id" {
  description = "ID of the private subnet (worker nodes)"
  value       = module.vpc.private_subnet_id
}

output "nat_gateway_public_ip" {
  description = "Public IP of the NAT Gateway — worker node internet traffic egresses from this IP"
  value       = module.vpc.nat_gateway_public_ip
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------
output "iam_role_arn" {
  description = "ARN of the IAM role attached to all Kubernetes nodes"
  value       = module.iam.role_arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile attached to all EC2 nodes"
  value       = module.iam.instance_profile_name
}
