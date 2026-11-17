# Showcase demo: one day on AWS, then tear down

A script for recording the pipeline running for real. The whole session takes about 1–2 hours and costs roughly US$1–3, which the AWS sign-up credits cover. Then everything is deleted.

> Record your screen for each scene (macOS: ⌘⇧5). Keep the GitHub Actions tab, a terminal and Grafana open side by side.

## 0. One-time prerequisites (≈15 min)

```bash
brew install awscli gh terraform   # skip the ones you already have
aws login                          # browser sign-in, short-lived credentials (AWS CLI ≥ 2.32), no access keys
aws configure set region us-east-1   # new AWS accounts can only launch servers in a few US regions
gh auth login
```

Optional but recommended:
- **Alerts on your phone:** in a Discord server, go to Server Settings → Integrations → Webhooks → New Webhook, copy the URL, and add `/slack` to the end. The setup script asks for it.
- **A GLM API key**, so the AI features answer live.

## 1. Infrastructure as code: create the server (≈5 min)

```bash
ALARM_EMAIL=you@example.com infra/demo/demo-up.sh
# USE_HTTPS=1 infra/demo/demo-up.sh   ← real HTTPS through <ip>.sslip.io
```

🎬 **Show:** `terraform apply` creating the VPC, firewall, encrypted disk, backup bucket, alarms, budget and OIDC role. Then the script filling in GitHub secrets on its own. Confirm the AWS email subscription.

## 2. Release v1.0.0: the full pipeline (≈10 min)

```bash
git tag v1.0.0 && git push origin v1.0.0
gh run watch
```

🎬 **Show:**
- The Actions graph: **Tests → Images → Deploy**.
- Inside Deploy: the job opening SSH *for its own IP only*, pulling the exact image, the `/ready` smoke test, and SSH closing again.
- The image job's Trivy scan, SBOM and provenance.
- The repo's **Packages** page (GHCR).

Then seed the databases with the `curl` commands the setup script printed, and open the app URL.

## 3. Observability (≈10 min)

Open `<url>/grafana` and sign in as `admin` with the password the setup script printed.

🎬 **Show:**
- The **Zync — Production Overview** dashboard: request rate, errors, latency, GLM calls and tokens, CPU, memory, disk and backup age.
- **Grafana → Explore → Loki**: `{service="backend"} | json`. Click a log line to show the `request_id`. Then copy the `X-Request-ID` from the browser devtools and search for it in Loki to find that exact request.

## 4. Incident: an alert fires and resolves (≈5 min)

```bash
IP=$(terraform -chdir=infra output -raw public_ip)
ssh -i ~/.ssh/zync_deploy ubuntu@$IP 'cd Zync && docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.monitoring.yml stop postgres'
```

🎬 **Show:** after about 2 minutes, **BackendNotReady** and **PostgresDown** fire in Grafana and arrive in Discord. Open `docs/RUNBOOK.md` at that alert and follow it:

```bash
ssh -i ~/.ssh/zync_deploy ubuntu@$IP 'cd Zync && docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.monitoring.yml start postgres'
```

Then the ✅ *resolved* message arrives.

## 5. A bad release rolls itself back (≈10 min). This is the best scene.

Ship a version whose readiness check always fails. The unit tests pass, so only the production smoke test can catch it:

```bash
git switch -c demo/broken-release
sed -i '' 's/^PROBE_TIMEOUT_S = 3.0$/PROBE_TIMEOUT_S = 0.000001  # demo: deliberately broken/' backend/health.py
git commit -qam "demo: deliberately break readiness check"
git tag v1.0.1 && git push origin v1.0.1
gh run watch
```

🎬 **Show:** Tests ✅ and Images ✅, then Deploy fails with `❌ 1.0.1 failed health checks`, followed by `↩️ Rolling back to 1.0.0`. The site never went down. Run `curl <url>/ready` to show it's still healthy on 1.0.0.

Clean up afterwards:

```bash
git switch main && git branch -D demo/broken-release
git push origin :refs/tags/v1.0.1 && git tag -d v1.0.1
```

**Manual rollback:** Actions → Deploy → *Run workflow* → `v1.0.0`.

## 6. Backups and restore (≈5 min)

```bash
ssh -i ~/.ssh/zync_deploy ubuntu@$IP
cd Zync
deploy/backup.sh          # dumps Postgres, Neo4j and Qdrant, uploads to encrypted S3
deploy/restore.sh         # lists the available backups
deploy/restore.sh <backup> qdrant   # restore one database (type 'restore' to confirm)
```

🎬 **Show:** the backup log, the S3 bucket in the AWS console, and the **Last successful backup** panel in Grafana switching to "just now".

## 7. Security evidence (no recording needed, screenshots are enough)

- GitHub → **Security → Code scanning**: 0 open alerts. CodeQL, Trivy and gitleaks all run on every push.
- The Actions tab: green runs for Test, Security, Docker Image CI, Terraform and Monitoring config.

## 8. Tear down (≈5 min)

```bash
infra/demo/demo-down.sh   # type 'destroy'
```

Check the AWS console: **EC2 → Instances** should be empty, and **Billing → Bills** should show only cents.

---

### If something goes wrong

| Symptom | Fix |
|---|---|
| `InvalidParameterCombination` / instance type not eligible | In `infra/demo/demo.tfvars`, set `instance_type = "t3.large"` |
| `This account is currently blocked` when creating the instance | New / Free plan accounts may only launch EC2 in `us-east-1`, `us-east-2` or `us-west-2`. Keep the demo's default `us-east-1` |
| `OptInRequired` for ap-southeast-5 | Enable Malaysia under Account → AWS Regions, then set `aws_region` in `infra/demo/demo.tfvars` |
| Deploy: `Missing .env` | Re-run `infra/demo/connect-github.sh` |
| Deploy can't SSH | Check that `AWS_DEPLOY_ROLE_ARN` is set: `gh variable list` |
| HTTPS certificate error with `USE_HTTPS=1` | Let's Encrypt may be rate-limiting sslip.io. Re-run `connect-github.sh` without `USE_HTTPS` and redeploy |
| Grafana panels empty | Wait 1–2 minutes for the first scrapes. Host panels need the server (they're empty locally on a Mac) |
