#!/usr/bin/env bash
# Restore Zync databases from a backup made by backup.sh.
#
#   deploy/restore.sh                       # list available backups
#   deploy/restore.sh 2026/11/17/20261117T183000Z [postgres|neo4j|qdrant|all]
#
# DESTRUCTIVE: replaces current database contents. Asks for confirmation.
set -euo pipefail

# shellcheck source=/dev/null
[ -f /etc/zync.env ] && . /etc/zync.env
APP_DIR="${APP_DIR:-/home/ubuntu/Zync}"
: "${BACKUP_BUCKET:?BACKUP_BUCKET not set (see /etc/zync.env)}"
REGION="${AWS_REGION:-ap-southeast-5}"
PROJECT="zync"

cd "$APP_DIR"
compose() { docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.monitoring.yml "$@"; }

if [ $# -eq 0 ]; then
  echo "Available backups (newest last):"
  aws s3 ls "s3://${BACKUP_BUCKET}/" --recursive --region "$REGION" \
    | awk '/SHA256SUMS$/ {sub("/SHA256SUMS$", "", $4); print "  " $4}' | tail -20
  exit 0
fi

BACKUP="$1"
WHAT="${2:-all}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

read -r -p "Restore '$WHAT' from $BACKUP? This OVERWRITES current data. Type 'restore' to continue: " ok
[ "$ok" = "restore" ] || { echo "Aborted."; exit 1; }

aws s3 cp --recursive --only-show-errors "s3://${BACKUP_BUCKET}/${BACKUP}/" "$WORK/" --region "$REGION"
( cd "$WORK" && sha256sum -c SHA256SUMS )

if [ "$WHAT" = all ] || [ "$WHAT" = postgres ]; then
  echo "Restoring Postgres…"
  compose exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner' \
    < "$WORK/postgres.dump"
fi

if [ "$WHAT" = all ] || [ "$WHAT" = neo4j ]; then
  echo "Restoring Neo4j…"
  NEO4J_IMAGE="$(compose config --images neo4j 2>/dev/null || echo neo4j:5.18)"
  compose stop neo4j
  docker run --rm -v "${PROJECT}_neo4j_data:/data" -v "$WORK:/backups" \
    "$NEO4J_IMAGE" neo4j-admin database load neo4j --from-path=/backups --overwrite-destination=true
  compose start neo4j
fi

if [ "$WHAT" = all ] || [ "$WHAT" = qdrant ]; then
  echo "Restoring Qdrant…"
  compose exec -T backend sh -c 'rm -rf /tmp/qdrant-restore && mkdir -p /tmp/qdrant-restore'
  compose cp "$WORK/qdrant/." backend:/tmp/qdrant-restore/
  compose exec -T backend python - <<'PY'
import pathlib, httpx
with httpx.Client(base_url="http://qdrant:6333", timeout=600) as qd:
    for snap in sorted(pathlib.Path("/tmp/qdrant-restore").glob("*.snapshot")):
        with snap.open("rb") as f:
            qd.post(
                f"/collections/{snap.stem}/snapshots/upload",
                params={"priority": "snapshot", "wait": "true"},
                files={"snapshot": (snap.name, f)},
            ).raise_for_status()
        print(f"  restored collection: {snap.stem}")
PY
  compose exec -T backend rm -rf /tmp/qdrant-restore
fi

echo "Restore finished. Check: curl -fsS http://localhost/ready (or https://<domain>/ready)"
