terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }

  # Remote state in S3 with native lockfile locking (Terraform >= 1.10).
  # Values live in backend.hcl (see backend.hcl.example):
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}
