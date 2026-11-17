# Zync — Malaysia's Sovereign REE Engineering Intelligence

[![Test](https://github.com/weeeijin/Zync/actions/workflows/test.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/test.yml) [![Security](https://github.com/weeeijin/Zync/actions/workflows/security.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/security.yml) [![Docker Image CI](https://github.com/weeeijin/Zync/actions/workflows/docker-image.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/docker-image.yml) [![Terraform](https://github.com/weeeijin/Zync/actions/workflows/terraform.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/terraform.yml) [![Monitoring config](https://github.com/weeeijin/Zync/actions/workflows/monitoring.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/monitoring.yml) [![Deploy](https://github.com/weeeijin/Zync/actions/workflows/deploy.yml/badge.svg)](https://github.com/weeeijin/Zync/actions/workflows/deploy.yml)

> Putting GLM-5.1's scientific reasoning at the exact point where Malaysia's RM 1 trillion rare earth ambition is won or lost.

Malaysia sits on RM 1 trillion in Rare Earth Element (REE) resources but lacks the hydrometallurgical engineering depth to process them independently. Every critical processing decision — which lixiviant to use, why yields are dropping, which zone to invest in — currently depends on foreign expertise or goes unmade. Zync changes that.

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

```text
 git push / PR ──► Test ───────── ruff · pip-audit · npm audit · pytest + coverage · eslint · build
             ├──► Security ───── gitleaks (history) · CodeQL (Python/JS/Actions) · Trivy IaC
             ├──► Docker CI ──── build → Trivy image scan (blocks CRITICAL) → GHCR + SBOM + provenance
             ├──► Terraform ──── fmt · validate · Trivy (blocks MEDIUM+)
             └──► Monitoring ─── promtool · amtool · loki · alloy · shellcheck

 git tag vX.Y.Z ─► Test ─► Images ─► Deploy (env: production)
                                      ├─ OIDC → open SSH for this runner only
                                      ├─ pull exact image tag, compose up --wait
                                      ├─ smoke test /ready ─✗─► automatic rollback
                                      └─ external smoke test → close SSH

 Production (AWS ap-southeast-5, Terraform)
   Internet ─► Caddy (auto-HTTPS, headers, 12MB limit) ─┬─► frontend (nginx, non-root)
                                                         ├─► backend  (FastAPI, non-root) ─► Neo4j · Postgres · Qdrant
                                                         └─► Grafana
   Prometheus ◄── backend /metrics · node · cAdvisor · Postgres · Qdrant · blackbox probes
   Alertmanager ─► Slack/Discord      Loki ◄── Alloy ◄── all container logs
   Nightly backups → encrypted S3 · daily EBS snapshots · uptime check from GitHub every 15 min
```

| Area | Where |
|---|---|
| CI/CD workflows | [`.github/workflows/`](.github/workflows/) |
| Infrastructure as code | [`infra/`](infra/) (see its [README](infra/README.md) for first-time setup) |
| Compose stacks | `docker-compose.yml` (base) · `.override.yml` (dev) · `.prod.yml` · `.monitoring.yml` |
| Monitoring config, alerts, dashboards | [`monitoring/`](monitoring/) |
| Backups and restore | [`deploy/backup.sh`](deploy/backup.sh) · [`deploy/restore.sh`](deploy/restore.sh) |
| What to do when an alert fires | [`docs/RUNBOOK.md`](docs/RUNBOOK.md) |

**Release:** `git tag v1.0.0 && git push origin v1.0.0`. **Roll back:** Actions → Deploy → Run workflow → enter a previous version.

**Try it yourself:**
- **Locally, for free:** `docker compose -f docker-compose.yml -f docker-compose.override.yml -f docker-compose.monitoring.yml -f docker-compose.monitoring.local.yml up -d`, then open Grafana at http://localhost:3000/grafana.
- **On AWS for a day:** `infra/demo/demo-up.sh` creates everything, and `infra/demo/demo-down.sh` deletes it. See [`docs/DEMO.md`](docs/DEMO.md) for the full showcase walkthrough: release, incident, automatic rollback, backup and restore.

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
├── monitoring/          # Prometheus, alert rules, Alertmanager, Loki, Alloy, Grafana
├── deploy/              # Caddyfile, backup.sh, restore.sh
├── docs/RUNBOOK.md      # Operations and incident response
├── .github/workflows/   # CI, security, images, Terraform, deploy, uptime
├── docker-compose.yml   # + .override (dev) / .prod / .monitoring overlays
├── .env.example
└── README.md
```

---

## Built by Team Gunners

Zync demonstrates that frontier AI reasoning — grounded in real Malaysian data and enforced by real Malaysian regulations — can close the hydrometallurgical expertise gap that currently forces Malaysia to export raw minerals instead of processing them independently.

*Malaysia moves from raw material exporter to sovereign REE processor.*
