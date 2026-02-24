output "control_plane_sg_id" {
  description = "ID of the control plane security group"
  value       = aws_security_group.control_plane.id
}

output "worker_sg_id" {
  description = "ID of the worker nodes security group"
  value       = aws_security_group.worker.id
}
