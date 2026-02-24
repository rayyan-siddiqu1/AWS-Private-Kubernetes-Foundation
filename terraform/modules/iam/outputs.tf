output "instance_profile_name" {
  description = "Name of the IAM instance profile to attach to EC2 nodes"
  value       = aws_iam_instance_profile.k8s_node.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM instance profile"
  value       = aws_iam_instance_profile.k8s_node.arn
}

output "role_name" {
  description = "Name of the IAM role for Kubernetes nodes"
  value       = aws_iam_role.k8s_node.name
}

output "role_arn" {
  description = "ARN of the IAM role for Kubernetes nodes"
  value       = aws_iam_role.k8s_node.arn
}
