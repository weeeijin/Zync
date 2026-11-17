# One-day showcase environment. Used by infra/demo/demo-up.sh.
environment = "demo"

# N. Virginia: new AWS accounts (and Free plan accounts) may only launch EC2 in
# us-east-1, us-east-2 and us-west-2 — elsewhere RunInstances fails with
# "This account is currently blocked". Older accounts can pick any region,
# e.g. ap-southeast-1 (Singapore) or ap-southeast-5 (Malaysia, opt-in).
aws_region = "us-east-1"

# 2 vCPU / 8 GiB — enough for the app, three databases and monitoring.
# m7i-flex.large is on AWS's free-tier-eligible list for new accounts; if your
# account rejects it, use t3.large (~US$0.10/hour, covered by sign-up credits).
instance_type       = "m7i-flex.large"
root_volume_size_gb = 30

# Demo teardown: let `terraform destroy` remove everything, keys included
allow_destroy_backups    = true
kms_deletion_window_days = 7
backup_retention_days    = 3

monthly_budget_usd = 5
