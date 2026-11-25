# Zync on Kubernetes (local, with kind)

The same stack as `docker-compose.yml`, running on a local Kubernetes cluster. kind ("Kubernetes IN Docker") runs a real cluster inside Docker on your laptop, for free.

```bash
brew install kind kubectl      # once
k8s/up.sh                      # create cluster → build + load images → deploy → seed
open http://localhost:8088
k8s/down.sh                    # delete the cluster
```

The first run takes about 10 minutes: building images, pulling database images and booting Neo4j.

## What runs

```
 localhost:8088 ─► [kind node :30080] ─► gateway (Caddy) ─┬─► frontend ×2 (nginx)
                                                          └─► backend (FastAPI) ─┬─► postgres  (StatefulSet + 1Gi volume)
                                                                                 ├─► neo4j     (StatefulSet + 2Gi volume)
                                                                                 └─► qdrant    (StatefulSet + 1Gi volume)
 seed Job (one-off): waits for /ready, then seeds Neo4j and Qdrant
```

## Compose → Kubernetes

| Docker Compose | Kubernetes here | Why |
|---|---|---|
| `services:` (stateless) | **Deployment** + **Service** (`backend`, `frontend`, `gateway`) | Deployments keep N copies running and replace crashed pods; a Service gives them one stable DNS name and load-balances |
| `services:` (databases) | **StatefulSet** + **volumeClaimTemplate** | A stable identity (`neo4j-0`) and a disk that follows the pod |
| `volumes:` | **PersistentVolumeClaim** | Storage that outlives pods |
| `.env` / `environment:` | **Secret** (`zync-secrets`) + **ConfigMap** (`zync-config`) | Secrets are kept apart from normal settings |
| `healthcheck:` | **startup / liveness / readiness probes** | Liveness restarts a stuck container; readiness only stops sending it traffic |
| `depends_on: service_healthy` | *(nothing)* + readiness probe | Pods start in any order; `/ready` keeps the backend out of rotation until the databases answer |
| `ports: "80:80"` on Caddy | **NodePort** Service + kind port mapping | In the cloud: a LoadBalancer Service or Ingress/Gateway |
| `restart: unless-stopped` | Built in | Kubernetes always restarts failed containers |
| One-off `curl` to seed | **Job** (`seed-job.yaml`) | Runs to completion, with retries |
| `mem_limit` | `resources.requests` / `limits` | Requests are used for scheduling; the limit triggers an out-of-memory kill |

## Pod security

Every pod, the databases included, runs with:

- `runAsNonRoot` and a fixed user: 10001+ for our own images; the databases use their images' built-in users (postgres 70, neo4j 7474, qdrant 1000)
- `readOnlyRootFilesystem: true`, with writable `emptyDir` volumes only where needed (`/tmp`, Postgres's socket directory, Caddy's `/data`). The exception is Neo4j, whose entrypoint edits its own config at startup
- `allowPrivilegeEscalation: false` and all Linux capabilities dropped (Caddy keeps only `NET_BIND_SERVICE`, see below)
- the `RuntimeDefault` seccomp profile, plus CPU and memory requests and limits

The Security workflow scans these manifests with Trivy on every push. The few accepted findings are listed, each with its reason, in [`.trivyignore.yaml`](../.trivyignore.yaml).

## Try it: Kubernetes in action

```bash
kubectl -n zync get all                                # everything in the namespace
kubectl -n zync get pods -w                            # watch pods live (Ctrl+C to stop)

# Self-healing: delete pods and watch replacements appear
kubectl -n zync delete pod -l app=frontend

# Scaling
kubectl -n zync scale deploy/frontend --replicas=3

# Readiness: stop Postgres and watch the backend go 0/1 (no traffic), then recover
kubectl -n zync scale statefulset/postgres --replicas=0
kubectl -n zync get pods -w
kubectl -n zync scale statefulset/postgres --replicas=1

# Rolling update + rollback
kubectl -n zync set image deploy/frontend frontend=zync-frontend:does-not-exist
kubectl -n zync rollout status deploy/frontend         # never finishes; old pods keep serving
kubectl -n zync rollout undo deploy/frontend

# Logs, details, a shell
kubectl -n zync logs deploy/backend -f
kubectl -n zync describe pod -l app=backend            # events explain most problems
kubectl -n zync exec -it postgres-0 -- psql -U zync
```

## Problems hit while building this

| Symptom | Cause | Fix |
|---|---|---|
| Neo4j `CrashLoopBackOff`: `Unrecognized setting ... PASSWORD` | The Neo4j image turns **every** `NEO4J_*` variable into a config setting, so `NEO4J_PASSWORD` became an invalid setting | Renamed it to `GRAPH_PASSWORD` and built `NEO4J_AUTH` from it |
| Caddy `exec /usr/bin/caddy: operation not permitted` | The binary has the `cap_net_bind_service` file capability; with every capability dropped, the kernel refuses to run it | `capabilities.add: ["NET_BIND_SERVICE"]` |
| Seeding Qdrant returned 500: `Read-only file system (os error 30)` | With `readOnlyRootFilesystem`, the HuggingFace downloader writes to `~/.cache/huggingface`, outside the mounted `~/.cache/fastembed` | Mount the cache volume over the whole `~/.cache`. The read-only setting found a write path nobody knew about |
| Trivy reported 64 misconfigurations once the manifests were scanned: databases running as root, all capabilities kept, no seccomp | The app pods were hardened but the databases kept image defaults | Ran each database as its image's non-root user, dropped capabilities, added seccomp, CPU limits and read-only filesystems. The remaining trade-offs are documented in `.trivyignore.yaml` |
| Qdrant `Permission denied` on its WAL after switching to non-root | Its existing data was written by root, and kind's local-path storage ignores `fsGroup` | Recreated the volume and reseeded (it's reproducible test data). On real clusters, `fsGroup` or a one-time `chown` Job handles this |
| Port 8080 already in use | Another app on the laptop | The gateway is published on **8088** |

## Next steps (not done yet)

- **NetworkPolicies:** only the backend may reach the databases
- **Prometheus + Grafana in the cluster** (kube-prometheus-stack via Helm)
- **Ingress / Gateway API** instead of NodePort
- **Helm chart or ArgoCD** to deploy from Git
- **CI:** create a kind cluster in GitHub Actions and run `up.sh` as an end-to-end test
