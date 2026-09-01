# Screenshot Checklist

These are not captured automatically — command-line evidence lives in
[`docs/evidence/`](../evidence/); these screenshots are the visual
complement for a portfolio/README. None of the images below exist yet.
Capture each, save it into this directory using the filename shown, and
update this checklist's status column.

| # | Screenshot | Filename | Status |
|---|---|---|---|
| 1 | GitHub Actions — a successful pipeline run (all jobs green) | `01-github-actions.png` | PENDING MANUAL CAPTURE |
| 2 | CloudForge frontend running in a browser (showing `Backend: OK` / `Database: connected`) | `02-frontend-running.png` | PENDING MANUAL CAPTURE |
| 3 | `kubectl get pods -A` output showing all namespaces healthy | `03-kubectl-get-pods.png` | PENDING MANUAL CAPTURE |
| 4 | ArgoCD UI (or `kubectl get application cloudforge -n argocd`) showing **Synced** / **Healthy** | `04-argocd-synced-healthy.png` | PENDING MANUAL CAPTURE |
| 5 | Grafana Kubernetes dashboard showing live CPU/memory for `cloudforge-dev` pods | `05-grafana-dashboard.png` | PENDING MANUAL CAPTURE |
| 6 | Prometheus targets page (`/targets`) showing `kubelet`, `kube-state-metrics`, `node-exporter` up | `06-prometheus-targets.png` | PENDING MANUAL CAPTURE |
| 7 | Failure/recovery demonstration — e.g. the `ImagePullBackOff` event from Phase 9's Test 6, or the pod-restart-count evidence from Test 5 | `07-failure-recovery.png` | PENDING MANUAL CAPTURE |
| 8 | `terraform plan` output summary (`Plan: 35 to add, 0 to change, 0 to destroy`) | `08-terraform-plan.png` | PENDING MANUAL CAPTURE |

## How to capture each one

1. **GitHub Actions**: open `https://github.com/AkhilTejaDoosari/cloudforge-platform/actions`, click the most recent successful run.
2. **Frontend**: `curl -H "Host: cloudforge.local" http://localhost/` won't show a browser view — open `http://cloudforge.local` in a browser with that host mapped, or `kubectl port-forward -n cloudforge-dev svc/frontend 8080:8080` and open `http://localhost:8080`.
3. **kubectl get pods**: `kubectl get pods -A` in a terminal.
4. **ArgoCD**: `kubectl port-forward -n argocd svc/argocd-server 8081:443` and open `https://localhost:8081` (self-signed cert — browser warning is expected for this local cluster), or just screenshot `kubectl get application cloudforge -n argocd`.
5. **Grafana**: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`, open `http://localhost:3000`, log in with `admin` / (`kubectl get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d`), open the "Kubernetes / Compute Resources / Namespace (Pods)" dashboard filtered to `cloudforge-dev`.
6. **Prometheus targets**: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090`, open `http://localhost:9090/targets`.
7. **Failure/recovery**: re-run one of Phase 9's tests (e.g. `kubectl delete pod -l app=backend -n cloudforge-dev` and screenshot the new pod appearing), or screenshot the relevant section of `docs/evidence/08-failure-recovery.txt`.
8. **Terraform plan**: `cd terraform/environments/dev && terraform plan` (needs fresh KodeKloud credentials configured — see `docs/phases.md`'s Phase 6 notes) and screenshot the summary line.
