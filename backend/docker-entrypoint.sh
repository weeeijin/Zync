#!/bin/sh
# Reset Prometheus multiprocess metric files left over from a previous run,
# otherwise counters from dead workers would be double-counted.
set -e
if [ -n "${PROMETHEUS_MULTIPROC_DIR:-}" ]; then
  rm -rf "${PROMETHEUS_MULTIPROC_DIR:?}"
  mkdir -p "$PROMETHEUS_MULTIPROC_DIR"
fi
exec "$@"
