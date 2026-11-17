#!/usr/bin/env bash
# Delete the showcase environment so it stops costing anything.
#
#   infra/demo/demo-down.sh
#   CONFIRM=destroy infra/demo/demo-down.sh   # no prompt (e.g. no terminal)
#
# Removes every AWS resource Terraform created (server, IP, backups, keys)
# and the GitHub settings that point at it, so the uptime check goes quiet.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INFRA="$(dirname "$HERE")"
KEY="${DEPLOY_KEY:-$HOME/.ssh/zync_deploy}"
REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

ok="${CONFIRM:-}"
if [ -z "$ok" ] && [ -t 0 ]; then
  read -r -p "This permanently deletes the demo server and its backups. Type 'destroy' to continue: " ok
fi
[ "$ok" = "destroy" ] || { echo "Aborted. Type 'destroy' at the prompt, or run: CONFIRM=destroy $0" >&2; exit 1; }

cd "$INFRA"
[ -f backend_override.tf ] || cp "$HERE/backend_override.tf" backend_override.tf
# Destroy in the region the resources actually live in (from state), even if
# demo.tfvars has since been pointed somewhere else
REGION="$(terraform output -raw aws_region 2>/dev/null || sed -n 's/^aws_region *= *"\(.*\)"/\1/p' "$HERE/demo.tfvars")"
terraform destroy -input=false -auto-approve \
  -var-file="$HERE/demo.tfvars" \
  -var "aws_region=$REGION" \
  -var "ssh_public_key=$(cat "$KEY.pub")"

# Snapshots are created by AWS Data Lifecycle Manager, not Terraform, so
# destroy doesn't remove them — delete the demo's ones explicitly.
echo "Deleting leftover EBS snapshots of the demo…"
for snap in $(aws ec2 describe-snapshots --region "$REGION" --owner-ids self \
    --filters Name=tag:Project,Values=zync Name=tag:Environment,Values=demo \
    --query 'Snapshots[].SnapshotId' --output text); do
  aws ec2 delete-snapshot --region "$REGION" --snapshot-id "$snap" && echo "  $snap"
done

echo "Removing GitHub settings that point at the deleted server…"
for v in PUBLIC_URL AWS_DEPLOY_ROLE_ARN AWS_SECURITY_GROUP_ID AWS_REGION; do
  gh variable delete "$v" --repo "$REPO" 2>/dev/null && echo "  variable $v" || true
done
for s in SERVER_HOST SERVER_USERNAME SERVER_KEY PROD_ENV_B64; do
  gh secret delete "$s" --repo "$REPO" --env production 2>/dev/null && echo "  secret   $s" || true
done

rm -f backend_override.tf "$HERE/.env.demo"
cat <<'EOF'

✅ Demo environment deleted. AWS charges have stopped.
   (The KMS key finishes deleting after its 7-day waiting period.)
   Double-check in the AWS console: EC2 → Instances should be empty.
EOF
