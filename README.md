# Zync — Malaysia's Sovereign REE Engineering Intelligence

[![Test](https://github.com/weeeijin/Zync/actions/workflows/test.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/test.yml) [![Security](https://github.com/weeeijin/Zync/actions/workflows/security.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/security.yml) [![Docker Image CI](https://github.com/weeeijin/Zync/actions/workflows/docker-image.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/docker-image.yml) [![Terraform](https://github.com/weeeijin/Zync/actions/workflows/terraform.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/terraform.yml) [![Monitoring config](https://github.com/weeeijin/Zync/actions/workflows/monitoring.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/monitoring.yml) [![Deploy](https://github.com/weeeijin/Zync/actions/workflows/deploy.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/deploy.yml)

> Putting GLM-5.1's scientific reasoning at the exact point where Malaysia's RM 1 trillion rare earth ambition is won or lost.

Malaysia sits on RM 1 trillion in Rare Earth Element (REE) resources but lacks the hydrometallurgical engineering depth to process them independently. Every critical processing decision — which lixiviant to use, why yields are dropping, which zone to invest in — currently depends on foreign expertise or goes unmade. Zync changes that.

> **About this repository: my DevOps project**
>
> The Zync application (the multi-agent AI backend, knowledge graph and React frontend) was built by **Team Gunners** at **UMHackathon 2026**; the original lives at [hmhhmm/Zync](https://github.com/hmhhmm/Zync). Their commits are kept in the history.
>
> **What I built on top of it ([@weeeijin](https://github.com/weeeijin)):** the production platform that takes the app from a laptop to the cloud.
> - **CI/CD:** GitHub Actions for tests, security scans and image builds, plus tag-based releases with smoke tests and automatic rollback
> - **Security:** CodeQL, Trivy, gitleaks, SBOM and provenance, GitHub OIDC (no stored cloud keys), hardened non-root containers
> - **Infrastructure as code:** Terraform on AWS (VPC, EC2, KMS, encrypted S3 backups, alarms, budget), with a one-command demo environment
> - **Observability:** Prometheus, Grafana, Loki and Alertmanager, with app instrumentation for HTTP and LLM metrics and request tracing
> - **Operations:** automated backups and restore, plus an incident runbook
>
> **Start here:** [DevOps & Operations](#devops--operations) · [Showcase walkthrough](docs/DEMO.md) · [Runbook](docs/RUNBOOK.md)

---

## Demo

| Resource | Link |
|---|---|
| Pitch Deck | [ZYNC](https://canva.link/cne9bpdxwz3f12l) |
| Demo Video | [Video](https://youtu.be/p5k_B3rlL3A) |
| Deployed Link | https://zync-beta.vercel.app/ |
| Documentation | [`documents/`](documents/) |

---

## The Three Decisions

Zync is not a chatbot. It is a **three-decision engine** backed by GLM-5.1's scientific reasoning, grounded in real Malaysian geological data, and enforced by live compliance checking against AELB, DOE, and JMG regulations.

| Decision | Question it answers | Key capability |
|---|---|---|
| **Process Diagnosis** | Why did my yield drop? | Streaming SciGLM causal reasoning |
| **Lixiviant Selection** | What chemistry for this soil? | GraphRAG + GLM function calling + 15-iteration optimization loop |
| **Zone Prioritisation** | Which zone do I invest in first? | 5-step scored ranking across economic, ESG, and infrastructure dimensions |

---

## What Makes This Different

Most AI systems in this space are:

```text
Frontend → one LLM call → response
```

Zync is:

```text
Frontend → Router → right agent → right database → grounded GLM reasoning → streamed response
```

Every recommendation is grounded in real data — not hallucination:

- **Agent 1** queries a Neo4j knowledge graph of real Malaysian REE processing history (10 verified cases across 8 states)
- **Agent 2** reasons from published chemistry literature via SciGLM
- **Agent 3** runs a live GLM optimization loop — each iteration simultaneously checked by Agent 4 for compliance
- **Agent 4** retrieves relevant regulations via hybrid vector + keyword search (Qdrant + fastembed) before reasoning
- **Agent 5** synthesises everything into a bilingual BM + EN report
- **Agent 6** scores multiple zones simultaneously across 5 dimensions — HREE strategic value, ESG regulatory exposure, infrastructure cost, 13MP alignment, and capital efficiency — and outputs a ranked investment recommendation in Bahasa Malaysia

---

## System Architecture
![Zync system architecture](documents/Screenshot%202026-05-03%20at%203.52.13%E2%80%AFAM.png)

The main idea is that every user action is routed through the backend agents, which pull from the graph, rules, and optimization data before producing the final recommendation.

---

## GLM Capability Layers

| Capability | Where it's used |
|---|---|
| Streaming `reasoning_content` | Agent 2 — chemistry thinking visible token by token |
| Function calling | Agent 2 — lixiviant knowledge base lookup mid-reasoning |
| Long context (202K tokens) | Agent 1 — ingests geological survey PDFs |
| JSON structured output | All agents — no freeform text, every output is typed |
| Bahasa Malaysia output | Agent 4 + Agent 6 — compliance and zone ranking in BM |
| Multi-variable scoring | Agent 6 — 5-step framework scoring across economic, ESG, and infrastructure dimensions simultaneously |

---

## Agent Pipeline

```text
Decision 1 & 2 — POST /api/pipeline
─────────────────────────────────────
Agent 0  Router          Classifies request, routes to correct pipeline
Agent 1  Historian       GraphRAG — traverses Neo4j knowledge graph
Agent 2  Chemist ★       SciGLM streaming reasoning, function calling
Agent 3  Optimizer       Live GLM iteration loop with compliance feedback
Agent 4  Compliance      Hybrid search (Qdrant) + AELB + DOE + JMG checks
Agent 5  Report Writer   Bilingual BM + EN report, PDF export

Decision 3 — POST /api/zone
─────────────────────────────────────
Agent 6  Zone Prioritiser   5-step scoring: HREE value, ESG, infrastructure
							Outputs ranked investment recommendation in BM + EN
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| AI | Z.ai GLM-5.1 (SciGLM, 202K context, streaming) |
| Backend | FastAPI, Python, Server-Sent Events |
| Knowledge Graph | Neo4j — GraphRAG for historical Malaysian REE cases |
| Vector Search | Qdrant + fastembed — hybrid search over regulatory documents |
| Iteration Storage | PostgreSQL — optimization iterations stored per session |
| Frontend | React + Vite, Bahasa Malaysia + English |

---

## Quick Start

### Prerequisites
- Docker Desktop
- GLM API key from [console.ilmu.ai](https://console.ilmu.ai) or [z.ai](https://z.ai)

### 1. Configure environment

```bash
cp .env.example .env
# Open .env and set at least:
# GLM_API_KEY, GLM_MODEL, ADMIN_SECRET, NEO4J_PASSWORD, POSTGRES_PASSWORD
```

Docker Compose reads the root `.env`. `docker compose` refuses to start if a required secret is missing.

### 2. Start everything

```bash
docker compose up --build
```

This merges `docker-compose.yml` with `docker-compose.override.yml`, which adds hot reload, source mounts and localhost-only ports.

- Backend API → `http://localhost:8000`
- Frontend → `http://localhost:5173`
- API docs → `http://localhost:8000/docs`
- Neo4j browser → `http://localhost:7474`

### 3. Seed databases (first run only)

```bash
# Uses the ADMIN_SECRET from your .env
export $(grep '^ADMIN_SECRET=' .env)

# Seed Neo4j with Malaysian REE historical cases
curl -X POST http://localhost:8000/api/admin/seed \
	-H "X-Admin-Secret: $ADMIN_SECRET"

# Seed Qdrant with regulatory documents
curl -X POST http://localhost:8000/api/admin/seed-qdrant \
	-H "X-Admin-Secret: $ADMIN_SECRET"

# Verify both are ready
curl http://localhost:8000/api/admin/status \
	-H "X-Admin-Secret: $ADMIN_SECRET"

# Readiness of every backing service
curl http://localhost:8000/ready
```

Expected output:

```json
{
	"neo4j": { "cases_in_graph": 10, "ready": true },
	"qdrant": { "regulations_count": 6, "ready": true }
}
```

### 4. Daily startup

```bash
docker compose up
# Stop with: docker compose down
```

### Production

See [DevOps & Operations](#devops--operations) below.

---

## DevOps & Operations

An end-to-end delivery and operations pipeline built around Zync: every push is tested and scanned, every release is an immutable image deployed by a git tag with automatic rollback, the infrastructure is Terraform, and production is observed through metrics, logs and alerts.

### Highlights

| Stage | What's in place |
|---|---|
| **CI** | Lint (ruff, eslint), unit tests with coverage (pytest), dependency audits (pip-audit, npm audit), frontend build, all on every push and PR |
| **Security** | gitleaks secret scanning over full history, CodeQL (Python, JS/TS, Actions), Trivy scans of images (CRITICAL blocks the build) and IaC, SHA-pinned actions, Dependabot. **0 open code-scanning alerts** |
| **Containers** | Multi-stage, non-root images (uid 10001 / 101), healthchecks, allowlist `.dockerignore`, packaging tools stripped, smoke-tested in CI. Published to GHCR with SBOM and build provenance |
| **CD** | `git tag vX.Y.Z` → tests → images → deploy. GitHub OIDC opens SSH for the runner's IP only, the server pulls the exact version, `/ready` is smoke-tested, failures roll back automatically, SSH is closed again |
| **Infrastructure as code** | Terraform for AWS: VPC with flow logs, least-privilege firewall, IMDSv2 EC2 with KMS-encrypted disk, Elastic IP, encrypted and versioned S3 backups, daily EBS snapshots, CloudWatch auto-recovery and alarms, a budget alarm, and a keyless GitHub deploy role |
| **Observability** | Prometheus, Grafana, Loki, Alloy and Alertmanager. HTTP and GLM metrics (latency, time to first token, tokens), JSON logs with a request ID that follows each request from Caddy to the backend, 22 alert rules, a provisioned dashboard, blackbox probes and an external uptime check |
| **Recovery** | Nightly Postgres, Neo4j and Qdrant backups with checksums to encrypted S3, a guarded restore script, one-click manual rollback, and a [runbook](docs/RUNBOOK.md) for every alert |
| **App hardening** | Production refuses to start with default secrets, errors return an ID instead of a stack trace, and the admin secret is compared in constant time. `/health` and `/ready` are separate probes |

### Pipeline

```text
 git push / PR ──► Test ───────── ruff · pip-audit · npm audit · pytest + coverage · eslint · build
             ├──► Security ───── gitleaks (history) · CodeQL (Python/JS/Actions) · Trivy IaC
             ├──► Docker CI ──── build → smoke test → Trivy image scan (blocks CRITICAL) → GHCR + SBOM + provenance
             ├──► Terraform ──── fmt · validate · Trivy (blocks MEDIUM+)
             └──► Monitoring ─── promtool · amtool · loki · alloy · shellcheck

 git tag vX.Y.Z ─► Test ─► Images ─► Deploy (env: production)
                                      ├─ OIDC → open SSH for this runner only
                                      ├─ pull exact image tag, compose up --wait
                                      ├─ smoke test /ready ─✗─► automatic rollback
                                      └─ external smoke test → close SSH

 Production (AWS, Terraform; region configurable)
   Internet ─► Caddy (auto-HTTPS, headers, 12MB limit) ─┬─► frontend (nginx, non-root)
                                                         ├─► backend  (FastAPI, non-root) ─► Neo4j · Postgres · Qdrant
                                                         └─► Grafana
   Prometheus ◄── backend /metrics · node · cAdvisor · Postgres · Qdrant · blackbox probes
   Alertmanager ─► Slack/Discord      Loki ◄── Alloy ◄── all container logs
   Nightly backups → encrypted S3 · daily EBS snapshots · uptime check from GitHub every 15 min
```

### Where everything lives

| Area | Where |
|---|---|
| CI/CD workflows | [`.github/workflows/`](.github/workflows/) |
| Infrastructure as code | [`infra/`](infra/) (see its [README](infra/README.md) for first-time setup) |
| One-command demo environment | [`infra/demo/`](infra/demo/): `demo-up.sh`, `connect-github.sh`, `demo-down.sh` |
| Compose stacks | `docker-compose.yml` (base) · `.override.yml` (dev) · `.prod.yml` · `.monitoring.yml` · `.monitoring.local.yml` |
| Monitoring config, alerts, dashboards | [`monitoring/`](monitoring/) |
| App instrumentation | [`backend/observability.py`](backend/observability.py) · [`backend/health.py`](backend/health.py) · [`backend/errors.py`](backend/errors.py) |
| Backups and restore | [`deploy/backup.sh`](deploy/backup.sh) · [`deploy/restore.sh`](deploy/restore.sh) |
| Incident response | [`docs/RUNBOOK.md`](docs/RUNBOOK.md) |
| Showcase walkthrough | [`docs/DEMO.md`](docs/DEMO.md) |

**Release:** `git tag v1.0.0 && git push origin v1.0.0`. **Roll back:** Actions → Deploy → Run workflow → enter a previous version.

### Try it yourself

**Locally, for free.** The full app plus the monitoring stack:

```bash
docker compose -f docker-compose.yml -f docker-compose.override.yml \
  -f docker-compose.monitoring.yml -f docker-compose.monitoring.local.yml up -d
open http://localhost:3000/grafana        # Zync — Production Overview dashboard

# Make an alert fire, then resolve it
docker compose stop postgres              # PostgresDown + BackendNotReady after ~2 min
docker compose start postgres
```

Host panels (CPU, disk) and the `node`/`cadvisor` targets stay empty on macOS; they need a Linux server.

**On AWS, for a day.** Sign in with `aws login`, then:

```bash
ALARM_EMAIL=you@example.com infra/demo/demo-up.sh     # infrastructure + server, wires GitHub secrets
CREATE_SERVER=false ALARM_EMAIL=you@example.com infra/demo/demo-up.sh   # everything except the EC2 server
CONFIRM=destroy infra/demo/demo-down.sh               # delete it all
```

The demo runs in `us-east-1`, where new AWS accounts can launch EC2, and has a US$5 budget alarm. `CREATE_SERVER=false` is for accounts whose vCPU quota is still too low for the server. See [`docs/DEMO.md`](docs/DEMO.md) for the scene-by-scene showcase: release, incident, automatic rollback, backup and restore.

### Lessons from running it for real

| Problem | Fix |
|---|---|
| Trivy blocked the frontend image (CRITICAL OpenSSL/brotli CVEs in the old base) | Upgraded to nginx 1.30 and `apk upgrade` at build time |
| A FastAPI upgrade silently dropped the `/api` prefix from metric labels | Route-template resolver plus a unit test that pins the labels |
| `terraform apply` failed on a colon in a DLM policy description, which `validate` didn't catch | Fixed the description. Some API rules only surface against the real cloud |
| New AWS accounts can only launch EC2 in a few US regions, with a 1 vCPU quota | Moved the demo to `us-east-1`, added the `create_server` toggle, region-scoped the bucket name |
| Long-lived access keys are easy to leak | Local access uses `aws login` (short-lived credentials); CI uses GitHub OIDC with no stored AWS keys |

---

## API Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/api/pipeline` | POST | Full 6-agent SSE pipeline (Decisions 1 & 2) |
| `/api/zone` | POST | Zone Prioritisation SSE stream (Decision 3) |
| `/api/validate` | POST | 5 known answer tests against Malaysian REE literature |
| `/api/upload/pdf` | POST | Geological survey PDF → auto-fill deposit form |
| `/api/admin/seed` | POST | Seed Neo4j with Malaysian REE case history |
| `/api/admin/seed-qdrant` | POST | Seed Qdrant with regulatory documents |
| `/api/admin/status` | GET | Verify all databases are ready |
| `/health` | GET | Liveness: the process is up |
| `/ready` | GET | Readiness: Postgres, Neo4j and Qdrant all reachable (503 if not) |

---

## Validation

Zync's scientific reasoning is validated against 5 published Malaysian REE sources:

| Test | Ground truth | Source |
|---|---|---|
| Laterite clay lixiviant | Ammonium sulfate, pH 4.0-4.5 | Fendy et al., BIO Web of Conferences 2023 |
| AELB thorium limit | 1.0 Bq/g (fail at pH 3.8) | AELB Regulations 1986, Regulation 26 |
| Low-ESG lixiviant | Magnesium/sodium sulfate | Sobri et al., Jurnal Teknologi 2025 |
| DOE discharge standard | pH 6-9, NH3-N < 10 mg/L | DOE EQA 1974 Schedule 10 Standard B |
| Insufficient data handling | Returns low confidence | OECD AI Principles 2023 |

Run validation:

```bash
curl -X POST http://localhost:8000/api/validate \
	-H "Content-Type: application/json" \
	-d '{}'
```

---

## Project Structure

```text
Zync/
├── backend/
│   ├── agents/          # Agent 0-6 — one file per agent
│   ├── prompts/         # System prompts for each GLM agent
│   ├── rag/             # GraphRAG, SQL RAG, hybrid search
│   ├── tools/           # Lixiviant KB, DOE checker, PDF extractor
│   └── tests/           # Validation and backend tests
├── data/
│   ├── known_cases/     # Malaysian REE historical cases (Neo4j seed)
│   ├── lixiviant_kb/    # Lixiviant knowledge base + DOE rules
│   ├── sample_deposits/ # Demo deposit profiles
│   └── validation/      # 5 known answer tests
├── documents/           # Proposal, deployment plan, QATD, demo deck
├── frontend/
│   └── src/
│       ├── components/  # UI, layout, trust, landing
│       ├── hooks/       # Data fetching and streaming hooks
│       └── modules/     # Diagnosis, Lixiviant, Zone Strategy
├── infra/               # Terraform: AWS VPC, EC2, S3 backups, alarms, GitHub OIDC
│   └── demo/            # One-command demo environment up / down
├── monitoring/          # Prometheus, alert rules, Alertmanager, Loki, Alloy, Grafana
├── deploy/              # Caddyfile, backup.sh, restore.sh
├── docs/
│   ├── RUNBOOK.md       # Operations and incident response
│   └── DEMO.md          # Showcase walkthrough (AWS or local)
├── .github/workflows/   # CI, security, images, Terraform, deploy, uptime
├── docker-compose.yml   # + .override (dev) / .prod / .monitoring overlays
├── .env.example
└── README.md
```

---

## Built by Team Gunners

Zync demonstrates that frontier AI reasoning — grounded in real Malaysian data and enforced by real Malaysian regulations — can close the hydrometallurgical expertise gap that currently forces Malaysia to export raw minerals instead of processing them independently.

*Malaysia moves from raw material exporter to sovereign REE processor.*
