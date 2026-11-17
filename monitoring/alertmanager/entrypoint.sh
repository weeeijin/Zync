#!/bin/sh
# Inject the Slack/Discord webhook from the environment (never committed to git).
# Without a webhook, alerts still show in the Alertmanager UI and Grafana.
set -eu
SRC=/etc/alertmanager/alertmanager.yml
CONFIG=/tmp/alertmanager.yml

if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  # Escape characters that are special in a sed replacement
  ESCAPED=$(printf '%s' "$SLACK_WEBHOOK_URL" | sed 's/[&|\\]/\\&/g')
  sed "s|__SLACK_WEBHOOK_URL__|${ESCAPED}|" "$SRC" > "$CONFIG"
else
  echo "ALERT_SLACK_WEBHOOK_URL not set — alerts are visible in the UI only" >&2
  # Keep the "slack" receiver but without any integration (valid, sends nothing)
  sed '/slack_configs:/,$d' "$SRC" > "$CONFIG"
fi

exec /bin/alertmanager --config.file="$CONFIG" --storage.path=/alertmanager
