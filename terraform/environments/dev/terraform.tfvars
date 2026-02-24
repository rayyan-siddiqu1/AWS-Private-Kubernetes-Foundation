# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
region       = "ap-south-1"
environment  = "dev"
project_name = "k8s-foundation"

# ---------------------------------------------------------------------------
# Networking — matches the architecture requirements
# ---------------------------------------------------------------------------
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"
availability_zone   = "ap-south-1a"

# ---------------------------------------------------------------------------
# EC2 Instance Types
# ---------------------------------------------------------------------------
instance_type_control_plane = "t3.medium"
instance_type_worker        = "t3.large"

# ---------------------------------------------------------------------------
# REQUIRED — Replace before running terraform apply
# ---------------------------------------------------------------------------

# Name of your existing EC2 key pair (no .pem extension)
key_name = "terraform-keypair"

# Your public IP address in CIDR notation.
# Find it with: curl -s ifconfig.me && echo "/32"
# This restricts SSH and Kubernetes API server access to your machine only.
my_ip = "203.190.146.202/32"
