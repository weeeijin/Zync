# Demo only: keep Terraform state on your laptop instead of S3.
# demo-up.sh copies this to infra/backend_override.tf (gitignored).
# Never use local state for a long-lived environment.
terraform {
  backend "local" {
    path = "demo.tfstate"
  }
}
