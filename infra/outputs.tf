output "public_ip" {
  description = "Elastic IP of the app server — set as the SERVER_HOST GitHub secret"
  value       = aws_eip.app.public_ip
}

output "public_url" {
  description = "Public URL — set as the PUBLIC_URL GitHub variable"
  value       = local.create_dns ? "https://${var.domain_name}" : "http://${aws_eip.app.public_ip}"
}

output "instance_id" {
  description = "EC2 instance ID (for `aws ssm start-session --target <id>`)"
  value       = aws_instance.app.id
}

output "ssh_command" {
  description = "SSH into the server"
  value       = "ssh ubuntu@${aws_eip.app.public_ip}"
}

output "backup_bucket" {
  description = "S3 bucket receiving nightly database dumps"
  value       = aws_s3_bucket.backups.bucket
}

output "aws_region" {
  description = "Region the stack runs in — set as the AWS_REGION GitHub variable"
  value       = var.aws_region
}
