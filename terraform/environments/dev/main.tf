# ---------------------------------------------------------------------------
# VPC — networking foundation
# Creates: VPC, public subnet, private subnet, IGW, NAT Gateway + EIP,
#          public + private route tables and their associations
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone
  project_name        = var.project_name
  environment         = var.environment
}

# ---------------------------------------------------------------------------
# IAM — instance roles and profiles
# Creates: IAM role, AmazonSSMManagedInstanceCore attachment,
#          minimal custom policy, and instance profile for all EC2 nodes
# ---------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment
}

# ---------------------------------------------------------------------------
# Security Groups — network access control
# Creates: control-plane-sg and worker-sg with all required rules
# Depends on VPC outputs for vpc_id and vpc_cidr_block
# ---------------------------------------------------------------------------
module "security_groups" {
  source = "../../modules/security-groups"

  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.vpc_cidr_block
  my_ip          = var.my_ip
  project_name   = var.project_name
  environment    = var.environment
}

# ---------------------------------------------------------------------------
# EC2 — compute instances
# Creates: 1 control plane (public subnet) + 2 workers (private subnet)
# Depends on VPC, security group, and IAM module outputs
# ---------------------------------------------------------------------------
module "ec2" {
  source = "../../modules/ec2"

  project_name                = var.project_name
  environment                 = var.environment
  public_subnet_id            = module.vpc.public_subnet_id
  private_subnet_id           = module.vpc.private_subnet_id
  control_plane_sg_id         = module.security_groups.control_plane_sg_id
  worker_sg_id                = module.security_groups.worker_sg_id
  instance_type_control_plane = var.instance_type_control_plane
  instance_type_worker        = var.instance_type_worker
  key_name                    = var.key_name
  instance_profile_name       = module.iam.instance_profile_name
}
