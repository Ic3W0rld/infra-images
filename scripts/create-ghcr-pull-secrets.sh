#!/usr/bin/env bash
# create-ghcr-pull-secrets.sh
# Creates/updates the `ghcr-pull` dockerconfigjson secret in every namespace that
# runs a private ghcr.io/ic3w0rld/* infra mirror image. Idempotent (apply-style).
#
# Reads GH_PAT_RW from the repo .env. PAT needs read:packages (write not required to pull).
# Run from the workstation with kubeconfig pointing at the prod cluster.
#
#   ./scripts/create-ghcr-pull-secrets.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
set -a; source "${REPO_ROOT}/.env"; set +a
: "${GH_PAT_RW:?GH_PAT_RW not set in ${REPO_ROOT}/.env}"

GHCR_USER="Ic3W0rld"
REGISTRY="ghcr.io"

# Namespaces running infra mirror images (from `kubectl get pods -A`).
NAMESPACES=(
  argocd cert-manager external-dns external-secrets kube-system
  local-path-storage loki metallb-system monitoring psql
  traefik vault zitadel
)

echo "Creating/updating 'ghcr-pull' in ${#NAMESPACES[@]} namespaces..."
for ns in "${NAMESPACES[@]}"; do
  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    echo "  SKIP $ns (namespace absent)"; continue
  fi
  kubectl create secret docker-registry ghcr-pull \
    --docker-server="$REGISTRY" \
    --docker-username="$GHCR_USER" \
    --docker-password="$GH_PAT_RW" \
    --docker-email="ic3cryst4l@proton.me" \
    --namespace="$ns" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "  OK   $ns"
done
echo "Done. Verify: kubectl get secret ghcr-pull -A"
