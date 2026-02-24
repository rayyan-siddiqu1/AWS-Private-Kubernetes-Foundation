variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
}

variable "public_subnet_id" {
  description = "ID of the public subnet — control plane is placed here"
  type        = string
}

variable "private_subnet_id" {
  description = "ID of the private subnet — worker nodes are placed here"
  type        = string
}

variable "control_plane_sg_id" {
  description = "Security group ID to attach to the control plane instance"
  type        = string
}

variable "worker_sg_id" {
  description = "Security group ID to attach to worker node instances"
  type        = string
}

variable "instance_type_control_plane" {
  description = "EC2 instance type for the Kubernetes control plane (min: t3.medium for 2vCPU/4GB)"
  type        = string
  default     = "t3.medium"
}

variable "instance_type_worker" {
  description = "EC2 instance type for Kubernetes worker nodes (min: t3.large for 4vCPU/8GB)"
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "Name of the AWS EC2 key pair used for SSH access"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name to attach to all EC2 instances"
  type        = string
}

variable "control_plane_volume_size" {
  description = "Root EBS volume size in GB for the control plane node"
  type        = number
  default     = 40
}

variable "worker_volume_size" {
  description = "Root EBS volume size in GB for each worker node"
  type        = number
  default     = 60
}
