# Zync infrastructure (Terraform, AWS)

One hardened EC2 server in the Malaysia region (`ap-southeast-5`) running the Docker Compose stack behind Caddy.

| File | What it creates |
|---|---|
| `main.tf` | VPC, public subnet, internet gateway, firewall (80/443 public, 22 restricted), VPC flow logs |
| `compute.tf` | Ubuntu 24.04 EC2 (IMDSv2, encrypted disk, SSM access), Elastic IP, optional Route 53 record |
| `backup.tf` | KMS key, encrypted and versioned S3 backup bucket, daily EBS snapshots (7 kept) |
| `alarms.tf` | Auto-recovery on host failure; optional email alarms for status checks and CPU |
| `github_oidc.tf` | Keyless role for GitHub Actions that opens SSH for the runner's IP only during a deploy |
| `templates/user_data.sh.tftpl` | First boot: Docker, security updates, fail2ban, swap, AWS CLI, nightly backup cron |

## First-time setup

```bash
# 0. Prerequisites: AWS CLI logged in (aws configure / aws sso login), Terraform >= 1.10
cd infra

# 1. Remote state bucket (once) — see backend.hcl.example
cp backend.hcl.example backend.hcl        # edit the bucket name
terraform init -backend-config=backend.hcl

# 2. Variables
cp terraform.tfvars.example terraform.tfvars   # set ssh_public_key, etc.

# 3. Review and apply
terraform plan -out tfplan
terraform apply tfplan
```

## Connect GitHub Actions to the new server

From `terraform output`:

| GitHub setting (Settings → Secrets and variables → Actions) | Value |
|---|---|
| Secret `SERVER_HOST` | `public_ip` |
| Secret `SERVER_USERNAME` | `ubuntu` |
| Secret `SERVER_KEY` | private key matching `ssh_public_key` |
| Variable `AWS_DEPLOY_ROLE_ARN` | `github_deploy_role_arn` |
| Variable `AWS_SECURITY_GROUP_ID` | `security_group_id` |
| Variable `AWS_REGION` | e.g. `ap-southeast-5` |
| Variable `PUBLIC_URL` | `public_url` |

Then create `/home/ubuntu/Zync/.env` on the server from `.env.example` with `APP_ENV=production`. Get a shell with `aws ssm start-session --target <instance_id>`, no SSH needed. Then push a `vX.Y.Z` tag to deploy.

## Notes

- **SSH:** `ssh_allowed_cidrs` can be empty. Deploys open port 22 for the runner's own IP and close it afterwards; admins use SSM Session Manager.
- **Upgrading the AMI or user_data** does not replace the server (`ignore_changes`). To rebuild on purpose, run `terraform apply -replace=aws_instance.app`, then restore from backups (see `docs/RUNBOOK.md`).
- **Cost (approx.):** t3.large ≈ US$70/month, plus 40 GB gp3, the Elastic IP, KMS and S3. Use `t3.medium` for demos at the risk of running out of memory.
