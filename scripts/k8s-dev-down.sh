#!/usr/bin/env bash
# Tears down the local kind cluster entirely. Fully reversible/local — no AWS
# resources are involved. Re-running scripts/k8s-dev-up.sh recreates everything.
set -euo pipefail

CLUSTER_NAME="cloudforge"
kind delete cluster --name "$CLUSTER_NAME"
