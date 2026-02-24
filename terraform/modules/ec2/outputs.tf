output "control_plane_public_ip" {
  description = "Public IP address of the Kubernetes control plane node"
  value       = aws_instance.control_plane.public_ip
}

output "control_plane_private_ip" {
  description = "Private IP address of the Kubernetes control plane node"
  value       = aws_instance.control_plane.private_ip
}

output "control_plane_instance_id" {
  description = "EC2 instance ID of the control plane node"
  value       = aws_instance.control_plane.id
}

output "control_plane_ami_id" {
  description = "AMI ID used by the control plane instance"
  value       = aws_instance.control_plane.ami
}

output "worker_private_ips" {
  description = "List of private IP addresses for all worker nodes"
  value       = aws_instance.worker[*].private_ip
}

output "worker_instance_ids" {
  description = "List of EC2 instance IDs for all worker nodes"
  value       = aws_instance.worker[*].id
}
