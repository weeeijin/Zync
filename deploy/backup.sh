#!/usr/bin/env bash
# Nightly backup of all Zync databases to S3 (scheduled by infra cloud-init).
#
#   Postgres → pg_dump (custom format, online)
#   Neo4j    → neo4j-admin dump (Community edition needs the DB stopped: ~10-30s)
#   Qdrant   → full storage snapshot via its API (online)
#
# Writes a Prometheus textfile metric so a missed/failed backup raises an alert.
set -euo pipefail

# shellcheck source=/dev/null
[ -f /etc/zync.env ] && . /etc/zync.env
APP_DIR="${APP_DIR:-/home/ubuntu/Zync}"
: "${BACKUP_BUCKET:?BACKUP_BUCKET not set (see /etc/zync.env)}"
METRICS_DIR="${METRICS_DIR:-/var/lib/node_exporter/textfile}"
PROJECT="zync"

cd "$APP_DIR"
compose() { docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.monitoring.yml "$@"; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
PREFIX="s3://${BACKUP_BUCKET}/$(date -u +%Y/%m/%d)/${STAMP}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

write_metric() { # $1 = 1 success / 0 failure
  mkdir -p "$METRICS_DIR"
  local tmp="$METRICS_DIR/.zync_backup.prom.$$"
  {
    echo "# HELP zync_backup_last_run_success 1 if the last backup run succeeded"
    echo "# TYPE zync_backup_last_run_success gauge"
    echo "zync_backup_last_run_success $1"
    if [ "$1" = 1 ]; then
      echo "# HELP zync_backup_last_success_timestamp_seconds Unix time of the last successful backup"
      echo "# TYPE zync_backup_last_success_timestamp_seconds gauge"
      echo "zync_backup_last_success_timestamp_seconds $(date +%s)"
      echo "# HELP zync_backup_size_bytes Total size of the last backup"
      echo "# TYPE zync_backup_size_bytes gauge"
      echo "zync_backup_size_bytes $(du -sb "$WORK" | cut -f1)"
    fi
  } > "$tmp"
  # Keep the last success timestamp if this run failed
  if [ "$1" = 0 ] && [ -f "$METRICS_DIR/zync_backup.prom" ]; then
    grep -E '^zync_backup_(last_success_timestamp_seconds|size_bytes)|^# (HELP|TYPE) zync_backup_(last_success|size)' \
      "$METRICS_DIR/zync_backup.prom" >> "$tmp" || true
  fi
  mv "$tmp" "$METRICS_DIR/zync_backup.prom"
}
trap 'write_metric 0; rm -rf "$WORK"' ERR

log() { echo "[$(date -u +%FT%TZ)] $*"; }

# ── Postgres ────────────────────────────────────────────────────────────────
log "Postgres: pg_dump"
compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$WORK/postgres.dump"

# ── Qdrant ──────────────────────────────────────────────────────────────────
log "Qdrant: per-collection snapshots"
compose exec -T backend sh -c 'rm -rf /tmp/qdrant-backup && mkdir -p /tmp/qdrant-backup'
compose exec -T backend python - <<'PY'
import httpx
base = "http://qdrant:6333"
with httpx.Client(base_url=base, timeout=600) as qd:
    for col in qd.get("/collections").json()["result"]["collections"]:
        name = col["name"]
        snap = qd.post(f"/collections/{name}/snapshots").raise_for_status().json()["result"]["name"]
        with qd.stream("GET", f"/collections/{name}/snapshots/{snap}") as r, \
             open(f"/tmp/qdrant-backup/{name}.snapshot", "wb") as f:
            r.raise_for_status()
            for chunk in r.iter_bytes():
                f.write(chunk)
        qd.delete(f"/collections/{name}/snapshots/{snap}")
        print(f"  snapshot: {name}")
PY
mkdir -p "$WORK/qdrant"
compose cp backend:/tmp/qdrant-backup/. "$WORK/qdrant/"
compose exec -T backend rm -rf /tmp/qdrant-backup

# ── Neo4j (brief stop: Community edition has no online backup) ──────────────
log "Neo4j: stop → dump → start"
NEO4J_IMAGE="$(compose config --images neo4j 2>/dev/null || echo neo4j:5.18)"
compose stop neo4j
if docker run --rm \
     -v "${PROJECT}_neo4j_data:/data" \
     -v "$WORK:/backups" \
     "$NEO4J_IMAGE" neo4j-admin database dump neo4j --to-path=/backups --overwrite-destination=true; then
  compose start neo4j
else
  compose start neo4j
  log "Neo4j dump failed"; write_metric 0; exit 1
fi

# ── Upload ──────────────────────────────────────────────────────────────────
( cd "$WORK" && find . -type f ! -name SHA256SUMS -print0 | xargs -0 sha256sum > SHA256SUMS )
log "Uploading to $PREFIX/"
aws s3 cp --recursive --only-show-errors "$WORK" "$PREFIX/" --region "${AWS_REGION:-ap-southeast-5}"

write_metric 1
log "Backup complete: $(du -sh "$WORK" | cut -f1) → $PREFIX/"
