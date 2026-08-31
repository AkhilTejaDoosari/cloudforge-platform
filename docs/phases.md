# Build Phases

| Phase | Scope | Status |
|---|---|---|
| 1 | Repository structure + simple application | ✅ Done |
| 2 | Dockerize frontend/backend/database, verify locally | ✅ Done |
| 3 | Deploy locally to Kubernetes, verify health | ⏳ Next |
| 4 | GitHub Actions CI (test, build, Trivy scan, push to ECR) | Not started |
| 5 | Modular AWS Terraform infrastructure | Not started |
| 6 | Provision ECR/EKS, deploy application | Not started |
| 7 | ArgoCD + GitOps | Not started |
| 8 | Prometheus, Grafana, Loki | Not started |
| 9 | Security hardening + operational testing | Not started |
| 10 | Failure testing, rollback, DR docs, final README | Not started |

## Phase 1 Notes

- Backend: FastAPI, two endpoints — `/health` (pure liveness) and `/api/status`
  (reports backend + database connectivity). Split deliberately to mirror the
  liveness/readiness distinction Kubernetes will use in Phase 3.
- Frontend: static HTML/CSS/JS, no build step. Calls `/api/status` and renders
  backend/database state. API base URL is set in `config.js` so it can be
  swapped per environment without rebuilding.
- Database: not running yet in this phase (no Docker/Postgres). The backend
  is written to fail gracefully — `/api/status` reports `database: disconnected`
  rather than crashing. Verified this behavior explicitly (see validation log
  in the phase 1 commit).
- Verified: `pytest` passes, backend runs via `uvicorn`, frontend fetches and
  renders live status against the real backend over HTTP on localhost.

## Phase 2 Notes

- Backend Dockerfile: multi-stage (`builder` installs deps to `--user` site-
  packages, `final` copies only that + app code into a slim runtime). Runs as
  non-root `appuser` (uid 10001).
- Frontend Dockerfile: single-stage — no build step exists to discard, so
  multi-stage would add nothing. Uses `nginxinc/nginx-unprivileged` (non-root,
  listens on 8080) instead of plain `nginx` to satisfy "non-root where
  practical" on the one image that's root by default.
- nginx reverse-proxies `/api/*` and `/health` to the backend container by
  Docker DNS name (`backend:8000`), so the browser only ever talks to one
  origin. No CORS configuration needed. This mirrors the Ingress pattern
  Kubernetes will use in Phase 3.
- `docker-compose.yml`: three services on one bridge network, real
  `HEALTHCHECK`s, `depends_on: condition: service_healthy` gating backend
  startup on Postgres actually being ready (`pg_isready`), not just started.
- DB credentials come from `.env` (gitignored) via `.env.example` template —
  never hardcoded in `docker-compose.yml`.
- **Bug found and fixed during validation:** the frontend's `wget` healthcheck
  used `http://localhost:8080/`, which resolved to `::1` first (per
  `/etc/hosts`) while nginx only binds IPv4 — busybox `wget` doesn't fall back
  to IPv4, so every healthcheck attempt failed with "Connection refused" even
  though the service was actually up and serving real traffic. Fixed by
  targeting `127.0.0.1` directly instead of `localhost`, in both the
  Dockerfile `HEALTHCHECK` and the compose-level override (compose's
  `healthcheck:` takes precedence over the Dockerfile's when both are
  defined). Confirmed via `docker inspect --format '{{json .State.Health}}'`
  before and after.
- Verified: `docker compose ps` shows all three containers `(healthy)`;
  `/api/status` reports `database: connected` end-to-end (direct curl to
  backend, curl through the frontend proxy, and a real Chrome page load);
  confirmed non-root via `docker compose exec <svc> id`; confirmed graceful
  degradation by stopping Postgres mid-run (`/health` stayed `ok`,
  `/api/status` correctly flipped to `disconnected`) and confirmed self-heal
  on restart with no backend restart needed.
