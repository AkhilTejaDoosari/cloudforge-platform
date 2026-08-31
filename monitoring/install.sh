#!/usr/bin/env bash
# Installs the observability stack (Prometheus, Grafana, Loki) into the
# local kind cluster. Idempotent: safe to re-run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null

kubectl get namespace monitoring >/dev/null 2>&1 || kubectl create namespace monitoring

echo "==> Installing kube-prometheus-stack (Prometheus + Grafana)"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values "$REPO_ROOT/monitoring/kube-prometheus-stack-values.yaml" \
  --wait --timeout 5m

echo "==> Installing loki-stack (Loki + Promtail)"
helm upgrade --install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=false \
  --set promtail.enabled=true \
  --wait --timeout 5m

# The loki-stack chart's auto-generated Grafana datasource ConfigMap sets
# isDefault: true, which conflicts with kube-prometheus-stack's Prometheus
# datasource (also default) and breaks Grafana's provisioning entirely with
# "Only one datasource per organization can be marked as default". Patch it
# every time this script runs, since `helm upgrade` recreates the ConfigMap
# from the chart's own values on each install/upgrade.
echo "==> Fixing loki-stack's datasource ConfigMap (isDefault conflict)"
kubectl get configmap loki-loki-stack -n monitoring -o yaml \
  | sed 's/isDefault: true/isDefault: false/' \
  | kubectl apply -f -

echo "==> Restarting Grafana to pick up the corrected datasource"
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring --timeout=120s

echo ""
echo "Done. Access with:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "  # then open http://localhost:3000 (user: admin)"
echo "  kubectl get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d; echo"
