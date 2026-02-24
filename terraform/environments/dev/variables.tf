variable "region" {
  description = "AWS region to deploy all resources into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name — used in resource names and tags (e.g., dev, staging, prod)"
  type        = string
}

variable "project_name" {
  description = "Project identifier — used as a prefix for all resource names and tags"
  type        = string
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (control plane node + NAT Gateway)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (worker nodes)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "AWS availability zone for subnet placement — both subnets share a single AZ for this cluster"
  type        = string
  default     = "us-east-1a"
}

# ---------------------------------------------------------------------------
# EC2
# ---------------------------------------------------------------------------
variable "instance_type_control_plane" {
  description = "EC2 instance type for the Kubernetes control plane — t3.medium provides 2 vCPU / 4 GB RAM"
  type        = string
  default     = "t3.medium"
}

variable "instance_type_worker" {
  description = "EC2 instance type for Kubernetes worker nodes — t3.large provides 4 vCPU / 8 GB RAM"
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "Name of the existing AWS EC2 key pair for SSH access to instances"
  type        = string
}

# ---------------------------------------------------------------------------
# Security
# ---------------------------------------------------------------------------
variable "my_ip" {
  description = <<-EOT
    Your public IP address in CIDR notation, used to scope SSH and Kubernetes
    API server access to a single trusted source.
    Example: "203.0.113.10/32"
    Find your IP: curl -s ifconfig.me && echo "/32"
  EOT
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip, 0))
    error_message = "my_ip must be a valid CIDR block (e.g., 203.0.113.10/32)."
  }
}
