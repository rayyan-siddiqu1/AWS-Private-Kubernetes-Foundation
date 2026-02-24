variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (control plane + NAT Gateway)"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (worker nodes)"
  type        = string
}

variable "availability_zone" {
  description = "AWS availability zone for subnet placement"
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
