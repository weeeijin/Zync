provider "aws" {
  region = var.aws_region

  # Every resource is tagged — makes cost tracking and cleanup trivial
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "github.com/weeeijin/Zync"
    }
  }
}
