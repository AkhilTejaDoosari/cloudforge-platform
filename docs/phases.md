# Build Phases

| Phase | Scope | Status |
|---|---|---|
| 1 | Repository structure + simple application | ✅ Done |
| 2 | Dockerize frontend/backend/database, verify locally | ✅ Done |
| 3 | Deploy locally to Kubernetes, verify health | ✅ Done |
| 4 | GitHub Actions CI (test, build, Trivy scan, push to ECR) | ✅ Done |
| 5 | Modular AWS Terraform infrastructure | ⏳ Next |
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

## Phase 3 Notes

- Local cluster: `kind` (Kubernetes-in-Docker), created via
  `scripts/kind-config.yaml` with host ports 80/443 mapped in for
  ingress-nginx and the control-plane node labeled `ingress-ready=true`.
  Chosen over enabling Docker Desktop's built-in Kubernetes because it's
  fully scriptable and doesn't require touching the pre-existing `default`
  kubeconfig context from another project.
- Kustomize `base/` + `overlays/dev/`: base holds environment-agnostic
  Deployments/Services/ConfigMap/HPA/Ingress/PVC; the dev overlay sets the
  `cloudforge-dev` namespace and generates the `postgres-credentials` Secret
  via `secretGenerator` from a gitignored `secrets.env` (only
  `secrets.env.example` is committed) — no base64 credentials ever land in a
  committed manifest.
- **Readiness probes target `/health`, not `/api/status`, deliberately.**
  Checking DB connectivity in readiness would fail every backend pod at once
  on a single Postgres blip, pulling the whole backend out of the Service —
  turning a dependency hiccup into a total outage. `/health` (no dependency)
  backs both liveness and readiness; `/api/status` stays available for the
  frontend UI without ever gating traffic.
- HPA on the backend only (min 2 / max 4, 70% CPU target) — it's the
  stateless, scalable tier. Requires `metrics-server`, which kind doesn't
  ship; installed manually and patched with `--kubelet-insecure-tls` since
  kind's kubelet certs aren't signed for metrics-server's default TLS
  verification.
- The frontend's nginx `proxy_pass http://backend:8000` from Phase 2 required
  **no changes** — Kubernetes Service DNS resolves the short name `backend`
  within a namespace exactly like Compose's network DNS did.
- Ingress routes only to the frontend Service; the frontend's own nginx
  config already handles `/api/*` and `/health` proxying internally, so no
  path-based routing rules were needed at the Ingress layer.
- `postgres-data` PVC uses `subPath: postgres` on the mount (not the PVC root
  directly) — a known gotcha where some volume provisioners leave a
  `lost+found` directory that makes Postgres refuse to initialize in a
  "non-empty" data directory.
- Verified, not assumed:
  - `kubectl get pods -n cloudforge-dev` — all 5 pods `Running`/`Ready`.
  - `kubectl exec` into the backend confirmed `DATABASE_URL` resolved
    correctly via Kubernetes' `$(VAR)` env expansion, and `/api/status`
    reported `database: connected`.
  - Full path tested for real: `curl -H "Host: cloudforge.local"
    http://localhost/api/status` → Ingress → frontend Service → frontend pod
    → backend Service → backend pod → Postgres, all the way through.
  - **Failure injection:** `kubectl scale deployment postgres --replicas=0`
    mid-run, then confirmed via `kubectl get endpoints backend` that both
    backend pods stayed in the Service's endpoint list the whole time (proving
    the readiness-probe design decision), while live Ingress traffic kept
    returning `/health: ok` and `/api/status: disconnected`. Scaled Postgres
    back to 1 and confirmed `/api/status` self-healed to `connected` with
    zero backend restarts.
  - `kubectl top pods` and `kubectl get hpa` confirmed metrics-server is
    reporting real per-pod CPU/memory and the HPA is computing utilization
    against it (`cpu: 4%/70%` at idle).
  - `scripts/k8s-dev-up.sh` re-run end-to-end against the already-running
    cluster to confirm it's genuinely idempotent (all resources reported
    `unchanged`, no errors).

## Phase 4 Notes

- Two-job pipeline: `test` (pytest) → `build-scan-push` (matrix over
  backend/frontend). Build failures fail fast before any image work happens.
- **Trivy policy was derived from actually scanning the images, not
  guessed.** Ran `trivy image` locally against both Phase 2/3 images first:
  - Backend: found `starlette` CVE-2024-47874 (DoS), pinned in by
    `fastapi==0.115.0`. Fixed by bumping to `fastapi==0.128.8` (→ starlette
    0.52.1), re-ran `pytest` (still 3/3 passing) and re-scanned to confirm.
  - Frontend: found 2 CRITICAL (`libcrypto3`/`libssl3`, OpenSSL heap
    overflow) in the `nginxinc/nginx-unprivileged:1.27-alpine` base image.
    Fixed by adding `RUN apk upgrade --no-cache` to the Dockerfile
    (temporarily switching to `USER root` for that one layer, then back to
    the non-root uid 101) — patches OS packages at build time instead of
    trusting the base tag's freshness. Confirmed still non-root afterward
    (`docker inspect --format '{{.Config.User}}'` → `101`) and confirmed the
    full compose stack still works end-to-end post-patch.
  - What's left after those fixes: only base-OS `HIGH` findings (openssl,
    libxml2, musl, etc. — one version behind their point release) and CVEs
    with **no fix available yet** (a base-OS `perl-base` CRITICAL in the
    Debian image, status `affected` not `fixed`). This is why the CI gate
    specifically uses `--ignore-unfixed`: failing the merge gate on a CVE
    nobody can currently patch just trains people to ignore red builds.
  - Final gate policy encoded in CI: `--severity CRITICAL --ignore-unfixed
    --exit-code 1` (blocks the merge). A separate non-blocking scan
    (`--severity HIGH,CRITICAL`, no ignore-unfixed, `exit-code 0`) uploads a
    SARIF report to GitHub's Security tab so nothing is hidden, it just
    doesn't block anything.
- ECR push step is gated on `github.ref == 'refs/heads/main' &&
  vars.AWS_ROLE_ARN != ''` — ECR and its OIDC trust role don't exist until
  Phase 5/6 provisions them via Terraform. Using a repo **variable** (not a
  secret) for the role ARN is deliberate: assuming the role still requires
  proving identity via GitHub's OIDC token exchange, so the ARN string alone
  isn't sensitive.
- Verified, not assumed:
  - `actionlint .github/workflows/ci.yml` — clean (schema, expression
    syntax, and embedded shell all validated).
  - Reproduced the exact CI gate command locally (`trivy image --severity
    CRITICAL --ignore-unfixed --exit-code 1`) against both freshly-rebuilt
    images and confirmed `exit code: 0` (would pass) for both.
  - Pushed to a real GitHub repo and watched the Actions run execute for
    real (see the run link in the phase 4 commit / PR, or `gh run list`).
