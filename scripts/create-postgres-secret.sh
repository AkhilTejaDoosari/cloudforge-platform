#!/usr/bin/env bash
# Creates the postgres-credentials Secret out-of-band, before any kustomize
# build/apply — required now that kubernetes/overlays/dev's kustomization.yaml
# no longer generates it (a secretGenerator reading a gitignored file breaks
# ArgoCD's `kustomize build` against the committed repo — see Phase 7 notes
# in docs/phases.md). Idempotent: safe to re-run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="cloudforge-dev"
SECRETS_ENV="$REPO_ROOT/kubernetes/overlays/dev/secrets.env"

if [ ! -f "$SECRETS_ENV" ]; then
  echo "==> No secrets.env found, copying from example (dev-only default credentials)"
  cp "$REPO_ROOT/kubernetes/overlays/dev/secrets.env.example" "$SECRETS_ENV"
fi

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

kubectl create secret generic postgres-credentials \
  --namespace "$NAMESPACE" \
  --from-env-file="$SECRETS_ENV" \
  --dry-run=client -o yaml | kubectl apply -f -
