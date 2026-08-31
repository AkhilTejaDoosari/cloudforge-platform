# Build Phases

| Phase | Scope | Status |
|---|---|---|
| 1 | Repository structure + simple application | ✅ Done |
| 2 | Dockerize frontend/backend/database, verify locally | ✅ Done |
| 3 | Deploy locally to Kubernetes, verify health | ✅ Done |
| 4 | GitHub Actions CI (test, build, Trivy scan, push to ECR) | ✅ Done |
| 5 | Modular AWS Terraform infrastructure | ✅ Done (code only — not applied) |
| 6 | Provision ECR/EKS, deploy application | ⚠️ Terraform code + plan validated; apply not run (KodeKloud session friction — see notes) |
| 7 | ArgoCD + GitOps | ✅ Done (on local kind cluster) |
| 8 | Prometheus, Grafana, Loki | ⏳ Next |
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
  - **Bug found on the first real run, fixed immediately:** both
    `build-scan-push` jobs failed at "Set up job" with `Unable to resolve
    action aquasecurity/trivy-action@0.28.0, unable to find version
    0.28.0` — the action's git tags are `v`-prefixed (`v0.28.0`), and the
    workflow referenced `0.28.0` without the `v`. `actionlint` had passed
    cleanly on this file — it validates workflow schema/expression syntax
    and shellchecks `run:` blocks, but does not verify that a pinned action
    ref actually resolves on GitHub. Fixed by pinning to `v0.36.0` (current
    latest) and confirmed via `gh api
    repos/aquasecurity/trivy-action/git/refs/tags/v0.36.0` before pushing
    again, along with every other action pin in the file. (Caught my own
    mistake on the first attempted fix too — the replacement still dropped
    the `v` prefix; verified with `grep` against the actual file content on
    the second attempt, not just the commit message.)
  - **Second real bug, second run:** both jobs got further (image built,
    Trivy ran) but the "Upload Trivy results to Security tab" step failed
    with `Resource not accessible by integration`. Root cause: GitHub
    Advanced Security (required for code scanning / SARIF upload) is free on
    public repos but not on private ones without a paid plan — and this is a
    private repo. Since that step was explicitly meant to be non-blocking,
    its failure shouldn't have stopped the rest of the job; it did because a
    failed step halts subsequent steps by default. Fixed with
    `continue-on-error: true` on that step — the merge-gate scan and (once
    Phase 5/6 lands) the ECR push now run regardless. If this repo is ever
    made public, the upload starts succeeding with no workflow changes
    needed.
  - **Fourth run: fully green.** `test` → both `build-scan-push` (backend,
    frontend) all passed — image build, both Trivy scans (including the real
    CRITICAL+ignore-unfixed gate, on GitHub's runner, not just locally), and
    the ECR steps correctly *skipped* (not failed) since `AWS_ROLE_ARN` isn't
    set. Repo: https://github.com/AkhilTejaDoosari/cloudforge-platform
    (private). Three real bugs found and fixed by actually watching runs
    execute instead of assuming a locally-validated workflow would work:
    a missing `v` prefix on an action tag, a private-repo Advanced Security
    limitation, and my own mistake repeating the first fix incorrectly.

## Phase 5 Notes

- Scope deliberately stops at `terraform fmt` / `terraform init -backend=false`
  / `terraform validate` / `tfsec` — no `terraform plan` or `apply`, no AWS
  credentials needed, nothing touches AWS at all. Provisioning is Phase 6.
- Five modules under `terraform/modules/`: `vpc`, `eks`, `ecr`, `rds`,
  `github-oidc`, each with its own `variables.tf`/`outputs.tf`/`versions.tf`,
  composed by `terraform/environments/dev/main.tf`. A separate
  `terraform/bootstrap` root creates the S3 state bucket — the classic
  chicken-and-egg problem (Terraform's own backend can't reference a bucket
  it hasn't created yet), so this one root legitimately uses local state.
  Uses Terraform ≥1.10's native S3 state locking (`use_lockfile`), so no
  DynamoDB lock table is needed.
- `ecr` module creates `cloudforge/backend` and `cloudforge/frontend` —
  matching the `REPO: cloudforge/${{ matrix.service }}` naming already
  hardcoded into the Phase 4 CI workflow.
- `rds` module never puts the DB password in a Terraform variable or
  default: `random_password` generates it at apply-time, stored only in
  Secrets Manager; the module outputs the secret's ARN, never the password.
  This is the production equivalent of Phase 3's gitignored
  `secrets.env` + Kustomize `secretGenerator` pattern.
- `github-oidc` module closes the loop back to Phase 4: its `role_arn`
  output is exactly what becomes the CI workflow's `AWS_ROLE_ARN` repo
  variable (Phase 6). Trust policy restricted via `StringLike` on
  `token.actions.githubusercontent.com:sub` to
  `repo:<org>/<repo>:ref:refs/heads/main` specifically — a PR from a fork
  presents a validly-signed GitHub OIDC token but for a different `sub`
  claim, and cannot assume this role. Handles the real-world gotcha where an
  AWS account can only have one OIDC provider per issuer URL
  (`create_oidc_provider` / `existing_oidc_provider_arn` variables let a
  second project in the same account reuse the first one's provider).
- **Security scan was run, not skipped, before considering this phase
  done.** Installed `tfsec` and ran it against the actual composed
  configuration (`environments/dev`, which pulls in every module via its
  local `source` references — running it against `terraform/` alone only
  scanned `bootstrap/`, since tfsec doesn't resolve relative module sources
  without a root that references them). First pass: 2 CRITICAL, 3 HIGH, 9
  MEDIUM, 4 LOW. Fixed the CRITICAL/HIGH findings that were genuinely
  actionable, same policy as the Trivy gate in Phase 4 — fix what's
  fixable, document what's an accepted tradeoff, never silently drop either:
  - `aws-eks-no-public-cluster-access` × the CIDR-restriction variant: EKS's
    public endpoint had no `public_access_cidrs` restriction (defaults to
    `0.0.0.0/0`). Fixed by adding a `data "http"` lookup of the caller's own
    current public IP (`https://checkip.amazonaws.com`) and restricting
    `public_access_cidrs` to that `/32` plus an optional allow-list
    variable, instead of leaving the endpoint open to the whole internet.
  - `aws-eks-no-public-cluster-access` (the "any public access at all"
    variant) is a separate, stricter rule that fires regardless of CIDR
    restriction — it's flagging the design decision itself
    (`endpoint_public_access = true`), not a fixable misconfiguration.
    Disabling it entirely would require a VPN/bastion to reach a personal
    dev cluster from a laptop, which is the right call for production and
    the wrong call here. Suppressed with an inline
    `#tfsec:ignore:aws-eks-no-public-cluster-access` plus a multi-line
    comment explaining the compensating control and the tradeoff — not
    silently dropped. (First attempt at the ignore comment put the
    explanation on the same line as the directive using `-- text`, which
    tfsec's comment parser didn't recognize; fixed by putting
    `#tfsec:ignore:...` alone on its own line immediately above the block,
    confirmed via a re-run showing `ignored: 1` instead of the finding
    still appearing.)
  - `aws-eks-enable-secret-encryption`: added a customer-managed KMS key
    (`aws_kms_key.eks_secrets`, rotation enabled) and wired it into the EKS
    cluster's `encryption_config` block for `secrets` — Kubernetes Secrets
    are now envelope-encrypted in etcd with a key this project controls,
    not just AWS's default one.
  - `aws-ec2-add-description-to-security-group-rule`-adjacent public-IP
    finding ×2: `map_public_ip_on_launch` was `true` on both public
    subnets despite nothing in the design needing it (the NAT Gateway gets
    its own explicit EIP; nothing else is ever launched into these
    subnets). Set to `false`.
  - Result after fixes: **0 CRITICAL, 0 HIGH** (1 explicitly-justified
    ignore), 9 MEDIUM / 4 LOW left as documented dev-environment tradeoffs
    (customer-managed KMS on S3/ECR/Secrets Manager too, RDS backup
    retention period, RDS IAM authentication, RDS deletion protection, RDS
    Performance Insights, VPC Flow Logs, S3 access logging) — worth
    revisiting in Phase 9 (security hardening), not blocking here for the
    same reason the Trivy gate doesn't block on every unfixed base-image
    CVE: real projects triage by severity and actionability, not by trying
    to reach zero findings on every tool immediately.
- Verified, not assumed:
  - `terraform fmt -recursive -check` — clean, no diffs, across all 6 roots
    (5 modules + bootstrap + environments/dev).
  - `terraform init -backend=false` succeeded for both `environments/dev`
    and `bootstrap` — confirms every module's `source` path resolves and
    every provider requirement is satisfiable, with zero AWS access.
  - `terraform validate` succeeded for both roots.
  - `tfsec` re-run after each fix, not just once at the end, to confirm each
    specific finding actually disappeared (or, for the one suppression,
    that it moved from "critical" to "ignored" in the summary counts) rather
    than assuming the fix was correct.
  - Reviewed `git status --short` before staging: `.terraform/` directories
    correctly excluded by the existing root `.gitignore`
    (`**/.terraform/`); `.terraform.lock.hcl` files correctly included
    (these should be committed, for reproducible provider version
    resolution — unlike state files, they contain no secrets or
    environment-specific data).

## Phase 6 Outcome (AWS)

The EKS module was rewritten for self-managed workers (launch template +
ASG, `eksClusterRole` naming, EC2_LINUX access entry) after `aws iam
simulate-principal-policy` (read-only, no resources created) showed the
KodeKloud sandbox account grants `eks:CreateCluster` and `iam:PassRole` to
`eks.amazonaws.com` (for that exact role name only) but neither
`eks:CreateNodegroup` nor `eks:CreateFargateProfile`. `fmt`/`validate`/`tfsec`
(0 CRITICAL, 0 HIGH) all passed, and `terraform plan` cleanly showed 35 to
add, 0 to destroy, with `aws_eks_node_group` and `aws_db_instance` both
absent as intended.

**`terraform apply` was never run.** KodeKloud's STS session tokens expired
twice during this work (once before the first apply attempt, once again
after a refresh), and the decision was made to stop AWS work for this
session rather than keep fighting credential lifecycle friction — no AWS
resources from Phase 6 were provisioned. The deliverable for this phase is
the code itself, its security validation, and a clean plan — not a running
EKS cluster. From here, CloudForge's Kubernetes runtime work (Phases
7-9) continues on the local `kind` cluster from Phase 3, which has been
running continuously since then.

## Phase 7 Notes (ArgoCD / GitOps)

- Installed ArgoCD (official `v2.13.2` manifests) into the existing `kind`
  cluster — all 7 pods (`application-controller`, `applicationset-controller`,
  `dex-server`, `notifications-controller`, `redis`, `repo-server`, `server`)
  reached `Running` within ~1 minute.
- Repo access for this private GitHub repo: a Kubernetes Secret labeled
  `argocd.argoproj.io/secret-type=repository`, populated via `gh auth token`
  through command substitution directly in the `kubectl create secret`
  invocation — the token was never printed to any tool output or written to
  a file, matching the credential-handling discipline established during
  the AWS work.
- **Real compatibility bug found and fixed before ArgoCD could even sync
  once:** `kubernetes/overlays/dev/kustomization.yaml`'s `secretGenerator`
  read a gitignored `secrets.env` file — fine for a local `kubectl apply -k`,
  but ArgoCD's repo-server runs `kustomize build` against the *committed*
  repo content, where that file never exists by design. Every sync would
  have failed at the build step. Fixed by removing the `secretGenerator`
  entirely and provisioning `postgres-credentials` out-of-band instead
  (`scripts/create-postgres-secret.sh`, idempotent) — the standard GitOps
  pattern where git holds a secret's *name*, never its generation logic or
  values. `scripts/k8s-dev-up.sh` updated to match. The already-running
  cluster's existing secret (created back in Phase 3) needed no changes.
- `argocd/application.yaml`: points at `kubernetes/overlays/dev` on `main`,
  `syncPolicy.automated` with `prune: true` and `selfHeal: true` — a manual
  `kubectl edit` drifting from Git gets reverted automatically, and a
  resource removed from Git gets deleted from the cluster, not just orphaned.
- First sync: **Synced / Healthy** immediately, with zero pod restarts —
  ArgoCD correctly recognized the already-running Phase 3 resources already
  matched the desired state (a clean "adopt existing resources" outcome,
  not a redeploy).
- **Real GitOps loop demonstrated end-to-end, not simulated:** bumped
  `frontend`'s `replicas: 2 → 3` in `kubernetes/base/frontend-deployment.yaml`,
  committed, pushed (`ef30a5d`). Forced an immediate ArgoCD refresh
  (`kubectl patch application ... argocd.argoproj.io/refresh=hard` — avoids
  waiting out the ~3 min default polling interval) and watched
  `status.sync.revision` update to exactly `ef30a5d...`, `status.sync.status`
  go `OutOfSync → Synced` and `status.health.status` go `Healthy →
  Progressing → Healthy`. Confirmed via `kubectl get pods`: 2 frontend pods
  before, 3 after (`frontend-658b58c97c-tbcfp`, age 10s), and
  `kubectl rollout status deployment/frontend` reported success. `/api/status`
  still returned `database: connected` throughout — no disruption to the
  running app.
