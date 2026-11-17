#!/bin/sh
# Write the public probe target from $PUBLIC_URL (file_sd), then start Prometheus.
set -eu
mkdir -p /prometheus/targets
if [ -n "${PUBLIC_URL:-}" ]; then
  printf '[{"targets":["%s/ready"],"labels":{"probe":"public"}}]\n' "${PUBLIC_URL%/}" > /prometheus/targets/public.json
else
  echo '[]' > /prometheus/targets/public.json
fi

exec /bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=15d \
  --storage.tsdb.retention.size=4GB \
  --web.enable-lifecycle
