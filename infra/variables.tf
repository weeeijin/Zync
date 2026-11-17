variable "project" {
  description = "Project name, used in resource names and tags"
  type        = string
  default     = "zync"
}

variable "environment" {
  description = "Deployment environment (production, staging, ...)"
  type        = string
  default     = "production"
}

variable "aws_region" {
  description = "AWS region. ap-southeast-5 = Malaysia (keeps data in-country)"
  type        = string
  default     = "ap-southeast-5"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet hosting the app server"
  type        = string
  default     = "10.20.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type. Neo4j + Qdrant + embeddings need ~6-8 GB RAM"
  type        = string
  default     = "t3.large"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size (OS, Docker images and database volumes)"
  type        = number
  default     = 40
}

variable "ssh_public_key" {
  description = "Public key used by GitHub Actions / admins to SSH in (contents of id_ed25519.pub)"
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs always allowed to SSH (port 22), e.g. [\"203.0.113.4/32\"]. Can be empty: CI opens 22 for its own IP per deploy, and admins can use SSM Session Manager"
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.ssh_allowed_cidrs, "0.0.0.0/0")
    error_message = "Do not open SSH to the whole internet; list specific CIDRs."
  }
}

variable "domain_name" {
  description = "Optional public hostname (e.g. zync.example.com). Requires route53_zone_id"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Optional Route 53 hosted zone ID in which to create the DNS record"
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  description = "How long database backups and EBS snapshots are kept"
  type        = number
  default     = 30
}

variable "alarm_email" {
  description = "Optional email for CloudWatch alarms (instance down, CPU). Confirm the subscription email"
  type        = string
  default     = ""
}
