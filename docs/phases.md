# Build Phases

| Phase | Scope | Status |
|---|---|---|
| 1 | Repository structure + simple application | ✅ Done |
| 2 | Dockerize frontend/backend/database, verify locally | ⏳ Next |
| 3 | Deploy locally to Kubernetes, verify health | Not started |
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
