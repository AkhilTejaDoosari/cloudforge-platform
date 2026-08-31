#!/usr/bin/env bash
# Brings up the full local Kubernetes environment for CloudForge: creates the
# kind cluster (if it doesn't exist), installs ingress-nginx + metrics-server,
# loads the locally-built Docker images, and applies the dev overlay.
set -euo pipefail

CLUSTER_NAME="cloudforge"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "==> Creating kind cluster '$CLUSTER_NAME'"
  kind create cluster --name "$CLUSTER_NAME" --config "$REPO_ROOT/scripts/kind-config.yaml"
else
  echo "==> kind cluster '$CLUSTER_NAME' already exists, reusing it"
fi

kubectl config use-context "kind-$CLUSTER_NAME"

if ! kubectl get ns ingress-nginx >/dev/null 2>&1; then
  echo "==> Installing ingress-nginx"
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml
  kubectl wait --namespace ingress-nginx --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller --timeout=180s
fi

if ! kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
  echo "==> Installing metrics-server"
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  kubectl patch deployment metrics-server -n kube-system --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
  kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s
fi

echo "==> Building and loading application images into kind"
docker build -t cloudforge-backend:local "$REPO_ROOT/app/backend"
docker build -t cloudforge-frontend:local "$REPO_ROOT/app/frontend"
kind load docker-image cloudforge-backend:local --name "$CLUSTER_NAME"
kind load docker-image cloudforge-frontend:local --name "$CLUSTER_NAME"

if [ ! -f "$REPO_ROOT/kubernetes/overlays/dev/secrets.env" ]; then
  echo "==> No secrets.env found, copying from example (dev-only default credentials)"
  cp "$REPO_ROOT/kubernetes/overlays/dev/secrets.env.example" "$REPO_ROOT/kubernetes/overlays/dev/secrets.env"
fi

echo "==> Applying kubernetes/overlays/dev"
kubectl apply -k "$REPO_ROOT/kubernetes/overlays/dev"

echo "==> Waiting for all pods to be ready"
kubectl wait --namespace cloudforge-dev --for=condition=ready pod --all --timeout=180s

echo ""
echo "Done. Test with:"
echo "  curl -H 'Host: cloudforge.local' http://localhost/api/status"
