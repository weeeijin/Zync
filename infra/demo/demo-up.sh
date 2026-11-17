#!/usr/bin/env bash
# Create the one-day showcase environment on AWS, then connect GitHub to it.
#
#   infra/demo/demo-up.sh
#
# Optional environment variables:
#   ALARM_EMAIL=you@example.com   budget + infrastructure alarm emails (recommended)
#   GLM_API_KEY=...               otherwise you're prompted (input hidden)
#   USE_HTTPS=1                   real HTTPS via <ip>.sslip.io + Let's Encrypt
#
# Tear down afterwards with infra/demo/demo-down.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INFRA="$(dirname "$HERE")"
KEY="${DEPLOY_KEY:-$HOME/.ssh/zync_deploy}"

say() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
need() { command -v "$1" >/dev/null || { echo "Missing '$1' — install it first ($2)"; exit 1; }; }

need aws "brew install awscli"
need terraform "brew install terraform"
need gh "brew install gh"
need ssh-keygen "comes with macOS"

say "Checking AWS and GitHub logins"
aws sts get-caller-identity --query 'Account' --output text >/dev/null \
  || { echo "Not logged in to AWS — run: aws configure"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Not logged in to GitHub — run: gh auth login"; exit 1; }

say "Deploy SSH key ($KEY)"
if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -N "" -C "zync-deploy" -f "$KEY" >/dev/null
  echo "Created a new key pair"
else
  echo "Reusing existing key"
fi

MY_IP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
echo "Your public IP: $MY_IP (allowed to SSH)"

say "Terraform apply (≈3 minutes)"
cd "$INFRA"
cp "$HERE/backend_override.tf" "$INFRA/backend_override.tf"
terraform init -input=false -upgrade >/dev/null
terraform apply -input=false -auto-approve \
  -var-file="$HERE/demo.tfvars" \
  -var "ssh_public_key=$(cat "$KEY.pub")" \
  -var "ssh_allowed_cidrs=[\"$MY_IP/32\"]" \
  -var "alarm_email=${ALARM_EMAIL:-}"

IP="$(terraform output -raw public_ip)"

say "Waiting for the server to finish its first-boot setup (Docker etc.)"
for _ in $(seq 1 40); do
  ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes \
    "ubuntu@$IP" true 2>/dev/null && break
  sleep 6
done
ssh -i "$KEY" -o BatchMode=yes "ubuntu@$IP" 'cloud-init status --wait >/dev/null; docker --version'

"$HERE/connect-github.sh"

if [ -n "${ALARM_EMAIL:-}" ]; then
  say "Check $ALARM_EMAIL and click 'Confirm subscription' from AWS Notifications"
fi
