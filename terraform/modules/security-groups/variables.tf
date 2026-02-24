variable "vpc_id" {
  description = "ID of the VPC where security groups will be created"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC — used to restrict NodePort access to internal traffic only"
  type        = string
}

variable "my_ip" {
  description = "Admin IP address in CIDR notation for SSH and Kubernetes API access (e.g., 1.2.3.4/32)"
  type        = string
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
}
