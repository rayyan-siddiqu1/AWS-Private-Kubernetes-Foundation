# ---------------------------------------------------------------------------
# Remote State Backend — S3 + DynamoDB
#
# PREREQUISITES (must exist before running `terraform init`):
#   1. S3 bucket with:
#        - Versioning enabled
#        - Server-side encryption (SSE-S3 or SSE-KMS)
#        - Block all public access enabled
#   2. DynamoDB table with:
#        - Partition key: "LockID" (String)
#        - On-demand or provisioned capacity
#
# Bootstrap these resources once by running:
#   aws s3api create-bucket --bucket <bucket-name> --region <region> \
#     --create-bucket-configuration LocationConstraint=<region>
#   aws s3api put-bucket-versioning --bucket <bucket-name> \
#     --versioning-configuration Status=Enabled
#   aws s3api put-bucket-encryption --bucket <bucket-name> \
#     --server-side-encryption-configuration \
#     '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#   aws dynamodb create-table --table-name <table-name> \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST --region <region>
#
# NOTE: Variables are NOT supported in backend blocks — values must be literals.
# ---------------------------------------------------------------------------
terraform {
  backend "s3" {
    bucket         = "my-tf-state-bucket----"
    key            = "dev/kubernetes/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "my-tf-lock-table-rayyan"
    encrypt        = true
  }
}
