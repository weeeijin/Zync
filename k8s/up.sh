#!/usr/bin/env bash
# Run Zync on a local Kubernetes cluster (kind), from scratch, in one go.
#
#   k8s/up.sh       then open http://localhost:8088
#   k8s/down.sh     to delete the cluster
#
# Needs: docker, kind, kubectl. GLM_API_KEY is taken from the environment or
# the repo's .env; without one the app runs but AI answers fail.
set -euo pipefail

cd "$(dirname "$0")/.."
CLUSTER=zync

say() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }

say "Cluster"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "Reusing kind cluster '$CLUSTER'"
else
  kind create cluster --name "$CLUSTER" --config k8s/kind-config.yaml
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

say "Build images and load them into the cluster"
docker build -q -f backend/Dockerfile -t zync-backend:k8s .
docker build -q --target prod -t zync-frontend:k8s frontend
kind load docker-image zync-backend:k8s zync-frontend:k8s --name "$CLUSTER"

say "Secrets (k8s/secrets.env)"
if [ ! -f k8s/secrets.env ]; then
  key="${GLM_API_KEY:-}"
  if [ -z "$key" ] && [ -f .env ]; then
    key="$(sed -n 's/^GLM_API_KEY=//p' .env | head -1)"
  fi
  # Production config insists on a key; a placeholder lets the app start
  key="${key:-not-set}"
  ( umask 077
    cat > k8s/secrets.env <<EOF
GLM_API_KEY=$key
ADMIN_SECRET=$(openssl rand -hex 16)
NEO4J_PASSWORD=$(openssl rand -hex 16)
POSTGRES_PASSWORD=$(openssl rand -hex 16)
EOF
  )
  echo "Created k8s/secrets.env with random passwords"
else
  echo "Using existing k8s/secrets.env"
fi

say "Apply manifests"
kubectl apply -k k8s

say "Wait for everything to be ready (Neo4j takes a few minutes the first time)"
kubectl -n zync rollout status statefulset/postgres statefulset/qdrant --timeout=5m
kubectl -n zync rollout status statefulset/neo4j --timeout=10m
kubectl -n zync rollout status deployment/backend deployment/frontend deployment/gateway --timeout=10m

say "Seed the databases (one-off Job)"
if ! kubectl -n zync get job seed >/dev/null 2>&1; then
  kubectl apply -f k8s/seed-job.yaml
fi
kubectl -n zync wait --for=condition=complete job/seed --timeout=10m
kubectl -n zync logs job/seed | tail -2

say "Done"
kubectl -n zync get pods
cat <<'EOF'

Open http://localhost:8088        (API readiness: http://localhost:8088/ready)
Try:  kubectl -n zync get all
      kubectl -n zync delete pod -l app=frontend     # watch Kubernetes replace them
      kubectl -n zync scale deploy/frontend --replicas=3
EOF
