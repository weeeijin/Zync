#!/usr/bin/env bash
# Wire GitHub Actions to the infrastructure Terraform just created:
#   • generates a production .env with strong random secrets
#   • stores it + the SSH key as secrets of the "production" environment
#   • sets the repository variables the workflows read
# Safe to re-run; it overwrites the previous values (and rotates the secrets).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INFRA="$(dirname "$HERE")"
KEY="${DEPLOY_KEY:-$HOME/.ssh/zync_deploy}"
REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
ENV_FILE="$HERE/.env.demo"

say() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
out() { terraform -chdir="$INFRA" output -raw "$1"; }
secret() { openssl rand -hex 24; }

IP="$(out public_ip)"
if [ "${USE_HTTPS:-0}" = 1 ]; then
  DOMAIN="${IP//./-}.sslip.io"   # free wildcard DNS → Caddy gets a Let's Encrypt cert
  PUBLIC_URL="https://$DOMAIN"
else
  DOMAIN=""
  PUBLIC_URL="http://$IP"
fi

# Answers can come from the environment (GLM_API_KEY, ALERT_WEBHOOK_URL);
# only prompt when there is a terminal to type into
WEBHOOK="${ALERT_WEBHOOK_URL:-}"
if [ -t 0 ]; then
  [ -n "${GLM_API_KEY:-}" ] || { read -r -s -p "GLM API key (Enter to skip — AI answers won't work): " GLM_API_KEY; echo; }
  [ -n "$WEBHOOK" ] || read -r -p "Discord/Slack webhook for alerts (Enter to skip): " WEBHOOK
fi
GLM_API_KEY="${GLM_API_KEY:-}"

say "Generating production .env → $ENV_FILE"
( umask 077
cat > "$ENV_FILE" <<EOF
APP_ENV=production
ADMIN_SECRET=$(secret)
CORS_ORIGINS=$PUBLIC_URL
GLM_API_KEY=${GLM_API_KEY}
GLM_MODEL=${GLM_MODEL:-glm-4-flash}
NEO4J_PASSWORD=$(secret)
POSTGRES_USER=zync
POSTGRES_PASSWORD=$(secret)
POSTGRES_DB=zync
DOMAIN=$DOMAIN
PUBLIC_URL=$PUBLIC_URL
GRAFANA_ADMIN_PASSWORD=$(secret | cut -c1-20)
ALERT_SLACK_WEBHOOK_URL=$WEBHOOK
WEB_CONCURRENCY=2
EOF
)

say "Configuring GitHub ($REPO)"
gh api -X PUT "repos/$REPO/environments/production" --silent
set_secret() { gh secret set "$1" --repo "$REPO" --env production --body "$2" >/dev/null && echo "  secret   $1"; }
set_var()    { gh variable set "$1" --repo "$REPO" --body "$2" >/dev/null && echo "  variable $1"; }

set_secret SERVER_HOST "$IP"
set_secret SERVER_USERNAME ubuntu
set_secret SERVER_KEY "$(cat "$KEY")"
set_secret PROD_ENV_B64 "$(base64 < "$ENV_FILE" | tr -d '\n')"
set_var AWS_DEPLOY_ROLE_ARN "$(out github_deploy_role_arn)"
set_var AWS_SECURITY_GROUP_ID "$(out security_group_id)"
set_var AWS_REGION "$(out aws_region)"
set_var PUBLIC_URL "$PUBLIC_URL"

GRAFANA_PW="$(grep '^GRAFANA_ADMIN_PASSWORD=' "$ENV_FILE" | cut -d= -f2)"
ADMIN_SECRET="$(grep '^ADMIN_SECRET=' "$ENV_FILE" | cut -d= -f2)"
cat <<EOF

✅ Ready. Next:

   git tag v1.0.0 && git push origin v1.0.0     # watch: gh run watch

   App:      $PUBLIC_URL
   Grafana:  $PUBLIC_URL/grafana   (admin / $GRAFANA_PW)

   Seed the databases once after the first deploy:
     curl -X POST $PUBLIC_URL/api/admin/seed        -H "X-Admin-Secret: $ADMIN_SECRET"
     curl -X POST $PUBLIC_URL/api/admin/seed-qdrant -H "X-Admin-Secret: $ADMIN_SECRET"

   Secrets are saved in $ENV_FILE (gitignored).
EOF
