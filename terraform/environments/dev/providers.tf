provider "aws" {
  region = var.region

  # Default tags propagate to all resources that support tagging.
  # Individual resources can still add or override tags using merge().
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
