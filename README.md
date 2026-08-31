# CloudForge — Production Kubernetes Platform on AWS

> **Status: Phase 4 of 10 complete.** This README grows with each phase; sections
> for Terraform, Kubernetes, CI/CD, GitOps, observability, and security will be
> filled in as those phases land. See [docs/phases.md](docs/phases.md) for the
> full roadmap and phase-by-phase log.

## Project Overview

CloudForge is a portfolio project demonstrating a production-grade DevOps/platform
engineering workflow: containerization, Kubernetes, Infrastructure as Code, CI/CD,
GitOps, observability, and security — all wrapped around a deliberately simple
application. **The application is not the point.** It exists only to give the
platform something real to build, deploy, and operate.

## Technology Stack

| Layer | Technology | Why |
|---|---|---|
| Backend | FastAPI (Python) | Async, minimal, built-in OpenAPI docs, industry-standard for lightweight services |
| Frontend | Static HTML/CSS/JS | No build tooling — keeps focus on infra, not frontend frameworks |
| Database | PostgreSQL | Real stateful dependency to justify RDS, Secrets, and connection management |
| Containers | Docker (multi-stage) | Reproducible builds, small images |
| Orchestration | Kubernetes (EKS) | Industry-standard container orchestration |
| IaC | Terraform | Modular, versioned, reviewable infrastructure |
| CI | GitHub Actions | Test → build → scan (Trivy) → publish to ECR (OIDC, no static AWS keys) |
| CD | ArgoCD (GitOps) | Declarative, auditable, git-as-source-of-truth deployments |
| Observability | Prometheus, Grafana, Loki | Metrics + dashboards + logs |
| Cloud | AWS (VPC, EKS, ECR, RDS, IAM, ALB, CloudWatch) | Real-world production target |

## Repository Structure

```
cloudforge-platform/
├── app/
│   ├── frontend/        # Static HTML/CSS/JS, calls backend /api/status
│   └── backend/         # FastAPI service, /health and /api/status endpoints
├── terraform/
│   ├── modules/         # vpc, eks, ecr, rds (Phase 5)
│   └── environments/dev # dev environment composition (Phase 5)
├── kubernetes/
│   ├── base/             # Kustomize base manifests: Deployments, Services,
│   │                     #   ConfigMap, HPA, Ingress, PVC
│   └── overlays/dev/     # namespace + secretGenerator for local kind use
├── argocd/                # ArgoCD Application definitions (Phase 7)
├── monitoring/             # Prometheus/Grafana/Loki config (Phase 8)
├── .github/workflows/       # CI pipelines (Phase 4)
├── docs/                     # Architecture notes, runbooks, phase log
└── scripts/                   # Helper scripts
```

## Application Architecture (Phase 2)

```mermaid
flowchart LR
    User((User Browser)) -->|":3000"| FE["Frontend container<br/>nginx-unprivileged, non-root<br/>listens :8080"]
    FE -->|"proxy_pass /api/*, /health"| BE["Backend container<br/>FastAPI, non-root<br/>listens :8000"]
    BE -->|"SELECT 1 (pool_pre_ping)"| DB[("Postgres container<br/>:5432, named volume")]
```

All three containers run on one Docker bridge network (`cloudforge`), each
with a real `HEALTHCHECK`, and `depends_on: condition: service_healthy` so the
backend doesn't start accepting the assumption that Postgres is ready until
`pg_isready` actually passes.

## Kubernetes Architecture (Phase 3)

```mermaid
flowchart LR
    User((Browser)) -->|"Host: cloudforge.local"| Ing["Ingress<br/>(ingress-nginx)"]
    Ing --> FE_SVC["Service: frontend<br/>:8080"]
    FE_SVC --> FE1["Pod: frontend"]
    FE_SVC --> FE2["Pod: frontend"]
    FE1 & FE2 -->|"proxy_pass /api,/health"| BE_SVC["Service: backend<br/>:8000"]
    BE_SVC --> BE1["Pod: backend"]
    BE_SVC --> BE2["Pod: backend"]
    HPA["HPA<br/>min 2 / max 4<br/>target 70% CPU"] -.scales.-> BE_SVC
    BE1 & BE2 --> PG_SVC["Service: postgres<br/>:5432"]
    PG_SVC --> PG["Pod: postgres<br/>(PVC-backed)"]
```

Same three-tier shape as Phase 2 — Kubernetes replaces Docker Compose's
bridge network + healthchecks with Services + probes, and adds an Ingress at
the edge and an HPA on the backend. The frontend's nginx config from Phase 2
needed **zero changes**: Kubernetes Service DNS resolves the short name
`backend` the same way Compose's network DNS did.

**Deliberate design decision — readiness probes target `/health`, not
`/api/status`:** if the backend's readiness probe checked database
connectivity, a single Postgres blip would fail *every* backend pod's
readiness at once and pull all of them from the Service's endpoints
simultaneously — turning one dependency hiccup into a total outage. Instead,
both liveness and readiness use `/health` (pure process check), so the
backend keeps serving traffic and reporting its real DB state via
`/api/status` even while Postgres is down. **Verified**, not just asserted:
scaled Postgres to 0 replicas mid-test and confirmed via
`kubectl get endpoints backend` that both backend pods stayed in the
Service's endpoint list the entire time, while live `curl` traffic through
the Ingress kept flowing (`/health: ok`, `/api/status: disconnected`), then
scaled Postgres back up and confirmed self-heal with no backend restart.

Secrets are never committed: `kubernetes/overlays/dev/secrets.env` (gitignored)
is read by Kustomize's `secretGenerator` at apply-time to produce the
`postgres-credentials` Secret — only `secrets.env.example` is in git. In
Phase 6+, this local Postgres Deployment is replaced by RDS for the AWS
environment; the in-cluster version exists purely so this phase could
exercise Deployments/Services/PVCs/probes without needing AWS yet.

- `GET /health` — pure liveness signal, no dependencies. Backing endpoint for
  Kubernetes liveness probes later.
- `GET /api/status` — readiness-style check; reports backend + database
  connectivity. Backing endpoint for Kubernetes readiness probes and what the
  frontend displays.

## Running Locally

### Option A — Docker Compose (Phase 2, recommended)

```bash
cp .env.example .env      # local-dev-only DB credentials, gitignored
docker compose up -d --build
docker compose ps         # wait until all three services show (healthy)
```

- Frontend: http://localhost:3000 — nginx serves the static files and
  reverse-proxies `/health` and `/api/*` to the backend, so the browser only
  ever talks to one origin (no CORS needed).
- Backend (direct, for debugging/Swagger UI): http://localhost:8000/docs
- Tear down: `docker compose down` (add `-v` to also delete the Postgres
  volume and start with a clean database).

**Verified behavior:** with all three containers up, `database` shows
`connected`. Stopping just Postgres (`docker compose stop postgres`) makes
`/api/status` correctly report `disconnected` while `/health` keeps returning
`ok` — the backend doesn't crash or need a restart, and self-heals back to
`connected` once Postgres is started again. This is `pool_pre_ping` doing its
job, and it's the same resilience story Kubernetes readiness probes will rely
on in Phase 3.

### Option B — bare processes (Phase 1 style, no Docker)

```bash
cd app/backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --port 8000
```
```bash
cd app/frontend
python3 -m http.server 3000
```

Without Postgres running, `/api/status` correctly reports `database: disconnected`
rather than crashing — the graceful-degradation design in action.

### Option C — local Kubernetes (Phase 3, kind)

```bash
brew install kind        # one-time
./scripts/k8s-dev-up.sh  # creates the cluster, installs ingress-nginx +
                          # metrics-server, builds/loads images, applies manifests
curl -H "Host: cloudforge.local" http://localhost/api/status
./scripts/k8s-dev-down.sh  # full teardown, fully reversible, all-local
```

See [docs/phases.md](docs/phases.md#phase-3-notes) for the Kubernetes
architecture, the readiness-probe design decision, and the failure-injection
test that validates it.

## CI Pipeline (Phase 4)

```mermaid
flowchart LR
    Push["push / PR to main"] --> Test["test job<br/>pytest"]
    Test --> Build["build-scan-push (matrix)<br/>backend, frontend"]
    Build --> Trivy1["Trivy: full report<br/>HIGH+CRITICAL, never fails<br/>→ GitHub Security tab"]
    Build --> Trivy2["Trivy: merge gate<br/>CRITICAL + fix available<br/>fails build if found"]
    Trivy2 -->|"main branch only,<br/>if AWS_ROLE_ARN set"| OIDC["AWS OIDC<br/>(no static keys)"]
    OIDC --> ECR["Amazon ECR"]
```

**Trivy policy, chosen from real scan results, not guessed:** the merge gate
fails only on `CRITICAL` vulnerabilities with a fix available
(`--ignore-unfixed`). A separate, non-blocking scan reports everything
(`HIGH`+`CRITICAL`, fixed or not) to GitHub's Security tab for visibility.
Gating on every unfixed base-image CVE would make the pipeline permanently
red for issues nobody can act on yet — that trains people to ignore red
builds, which defeats the point. See
[docs/phases.md](docs/phases.md#phase-4-notes) for the actual vulnerabilities
found and fixed while building this (a real `starlette` CVE fixed via a
`fastapi` version bump, and a real `openssl` CRITICAL in the frontend's
Alpine base fixed by patching OS packages at build time).

**ECR publish is gated behind `vars.AWS_ROLE_ARN`, not always attempted** —
ECR doesn't exist until Phase 5/6 provisions it via Terraform, so this step
skips gracefully until then instead of leaving the pipeline permanently red.

**Live and verified, not just locally validated:** pushed to
[github.com/AkhilTejaDoosari/cloudforge-platform](https://github.com/AkhilTejaDoosari/cloudforge-platform)
(private) and watched real Actions runs execute. Found and fixed three real
bugs this way that local `actionlint` validation didn't catch — a missing `v`
prefix on a pinned action tag (actionlint checks syntax, not whether a ref
resolves on GitHub) and a private-repo GitHub Advanced Security limitation on
SARIF upload. See [docs/phases.md](docs/phases.md#phase-4-notes) for details.

## Tests

```bash
cd app/backend
pytest -v
```

## Roadmap

See [docs/phases.md](docs/phases.md).

## Security Decisions

- No secrets are ever committed. `.gitignore` blocks `.env`, `*.tfvars`, `*.pem`,
  kubeconfig files, and Terraform state.
- Database credentials are always injected via environment variables /
  Kubernetes Secrets, never hard-coded.
- (More decisions added as each phase introduces new security surface.)
