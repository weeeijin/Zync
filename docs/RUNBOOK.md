# Zync Operations Runbook

What to do when something happens in production. Commands run on the server in `/home/ubuntu/Zync` unless noted.

```bash
# Shortcut used below
alias dc='docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.monitoring.yml'
```

**Get a shell:** `aws ssm start-session --target <instance_id>`. This needs no SSH key or open port. You can also `ssh ubuntu@<ip>` if your IP is in `ssh_allowed_cidrs`.

**Monitoring UIs:**
- Grafana: `https://<domain>/grafana`, user `admin`, password `GRAFANA_ADMIN_PASSWORD`.
- Prometheus and Alertmanager: run `ssh -L 9090:localhost:9090 -L 9093:localhost:9093 ubuntu@<ip>`, then open http://localhost:9090 and http://localhost:9093.

---

## Releases

| Task | How |
|---|---|
| **Release** | `git tag v1.4.0 && git push origin v1.4.0`. This runs tests, builds and scans the images, publishes them to GHCR, deploys, runs a smoke test, and rolls back automatically if the smoke test fails. |
| **Roll back** | GitHub → Actions → **Deploy** → *Run workflow* → `version: v1.3.2`. Any earlier release can be redeployed in about 2 minutes. |
| **See what's running** | `cat .deployed_version`, `tail .deploy_history`, `dc ps` |
| **Logs** | Grafana → Explore → Loki: `{service="backend"} \| json \| level="error"`. On the box: `dc logs -f --tail=200 backend` |
| **Find one request** | Copy the `X-Request-ID` response header (browser devtools), then in Loki: `{service=~"backend\|caddy"} \|= "<id>"` |

## Alerts

### PublicEndpointDown (critical)
The site doesn't answer from the internet.
1. Check whether the server is up: `aws ec2 describe-instance-status --instance-ids <id>`. Infrastructure alarms auto-recover host failures.
2. Check whether Caddy is running: `dc ps caddy`, then `dc logs --tail=100 caddy`.
3. Check DNS and TLS: `dig +short <domain>` should return the Elastic IP. Caddy logs show ACME errors.
4. Check the security group: 80/443 must be open (managed by Terraform, so look for drift with `terraform plan`).

### BackendNotReady (critical)
`/ready` reports a database as unreachable.
1. See which one: `dc exec backend python -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8000/ready').read().decode())"`
2. `dc ps`, then `dc logs --tail=100 <neo4j|postgres|qdrant>`.
3. Out of memory? Run `dmesg -T | grep -i oom` and check the *Container memory* panel. Then `dc restart <service>`.
4. Disk full? See **HostDiskAlmostFull**.

### HighErrorRate (critical)
More than 5% of API requests are returning 5xx errors.
1. Grafana → *Responses by status* and *Request rate by route*: which route is failing?
2. Loki: `{service="backend", level="error"}`. Each error has an `error_id` that matches what the user saw.
3. If it started right after a deploy, **roll back first, debug later**.

### LLMErrorRateHigh (critical) / LLMSlow (warning)
GLM calls are failing or slow. Check the `outcome` label on *GLM calls by outcome*:
- `http_401` / `http_403`: the API key is invalid or expired. Rotate `GLM_API_KEY` in `.env`, then run `dc up -d backend`.
- `http_429`: rate limit or quota. Check the provider console and reduce traffic.
- `timeout` / `http_5xx`: the provider is degraded. Check the provider's status page. Nothing to fix on our side.

### LLMTokenSpike (warning)
Token usage is 3× higher than the same hour yesterday. That can mean abuse, a retry loop, or a viral moment.
- In Loki, look at requests by `client_ip`: `sum by (client_ip) (count_over_time({service="backend"} | json [1h]))`
- If it's abuse, add a rate limit in Caddy or block the IP in the security group.

### HostDiskAlmostFull / HostDiskWillFillIn24h
1. `df -h /`, then `docker system df`
2. `docker image prune -af` removes old image versions; the current version stays in GHCR.
3. Check the *Container memory* panel and volume sizes: `docker system df -v | head -40`. Loki and Prometheus have size and time retention limits.
4. To grow the disk, raise `root_volume_size_gb` in Terraform, run `terraform apply`, then `sudo growpart /dev/nvme0n1 1 && sudo resize2fs /dev/nvme0n1p1`.

### HostMemoryLow / ContainerNearMemoryLimit
Find the largest container in the *Container memory* panel. Neo4j's heap is capped in `docker-compose.prod.yml`. For a lasting fix, move to a larger `instance_type` (Terraform; this needs a stop and start).

### ContainerRestarting
Run `dc ps` (look at the restart counts), then `dc logs --tail=200 <service>`. An `OOMKilled` status in `docker inspect <container> | jq '.[0].State'` means the memory limit is too low.

### BackupFailed / BackupStale / BackupNeverRan
1. `tail -100 /var/log/zync-backup.log`
2. Run it by hand: `deploy/backup.sh`
3. Common causes: the instance role can't reach S3 (`aws sts get-caller-identity`), the disk is full, or `/etc/zync.env` is missing.

### TLSCertificateExpiringSoon
Caddy renews certificates 30 days before expiry, so this alert means renewal has failed. Run `dc logs caddy | grep -i acme`. Port 80 must be reachable for the ACME challenge, and DNS must point at the server.

### Watchdog
Always firing on purpose: it proves the alerting pipeline works. It goes to the `null` receiver. If it's ever *missing* in Alertmanager, Prometheus or Alertmanager is broken.

---

## Backups & restore

- **Nightly** at 02:30 MYT, `deploy/backup.sh` dumps Postgres, Neo4j and Qdrant and uploads them to the encrypted S3 bucket. Backups are kept for 30 days.
- **Daily EBS snapshots** of the whole disk are kept for 7 days. Use these to recover the entire server.
- Restore one or all databases:

```bash
deploy/restore.sh                                     # list backups
deploy/restore.sh 2026/11/17/20261117T183000Z neo4j   # or postgres | qdrant | all
```

**Test the restore once a quarter** (see the drill below). A backup that has never been restored doesn't count as a backup.

### Restore drill (quarterly)
1. `terraform workspace new drill && terraform apply -var environment=drill`. This creates a throwaway copy of the infrastructure.
2. Deploy the current release to it, then run `deploy/restore.sh <latest> all`.
3. Check that `/ready` is OK and that `/api/admin/status` shows the case and regulation counts.
4. `terraform destroy`, then write down how long it took. That's your real recovery time.

## Rebuilding the server from scratch
1. `terraform apply -replace=aws_instance.app`. This creates a new server with the same IP, DNS and backup bucket.
2. Recreate `/home/ubuntu/Zync/.env` (keep a copy in your password manager).
3. GitHub → Actions → Deploy → run with the current version.
4. `deploy/restore.sh <latest> all`

## Secrets rotation
| Secret | Where | Rotate by |
|---|---|---|
| GLM API key | `.env` on the server | edit `.env`, then `dc up -d backend` |
| DB passwords | `.env` | `ALTER USER` in Postgres or `neo4j-admin dbms set-initial-password` on a fresh volume, update `.env`, then `dc up -d` |
| `ADMIN_SECRET`, `GRAFANA_ADMIN_PASSWORD` | `.env` | edit `.env`, then `dc up -d backend grafana` |
| Deploy SSH key | GitHub secret `SERVER_KEY` and Terraform `ssh_public_key` | new key pair, `terraform apply`, update the secret |
| AWS access from CI | none stored (OIDC) | nothing to rotate |
