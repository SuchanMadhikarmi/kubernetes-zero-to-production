#!/usr/bin/env bash
#
# setup-kind.sh
#
# Purpose: Create a kind cluster suitable for running the labs in this
#          repository. Defaults to a 3-node cluster (1 control plane,
#          2 workers) named "k8s-zero-to-hero".
#
# Usage:
#   ./setup-kind.sh [cluster-name]
#   ./setup-kind.sh my-cluster
#
# Idempotent: safe to run again; if the cluster exists it is reported.

set -euo pipefail

CLUSTER_NAME="${1:-k8s-zero-to-hero}"
CONFIG_FILE="$(mktemp)"

if ! command -v kind >/dev/null 2>&1; then
  echo "ERROR: 'kind' is not installed. Install it first: https://kind.sigs.k8s.io/docs/user/quick-start/" >&2
  exit 1
fi

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "Cluster '${CLUSTER_NAME}' already exists."
  kind get clusters
  exit 0
fi

cat > "${CONFIG_FILE}" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
- role: worker
- role: worker
EOF

echo "Creating kind cluster '${CLUSTER_NAME}'..."
kind create cluster --config "${CONFIG_FILE}"
rm -f "${CONFIG_FILE}"

echo
echo "Cluster ready. Verify with:"
echo "  kubectl cluster-info"
echo "  kubectl get nodes"
