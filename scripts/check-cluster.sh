#!/usr/bin/env bash
#
# check-cluster.sh
#
# Purpose: Verify cluster health and tooling before running labs. Checks
#          that kubectl can reach the API server, nodes are Ready, and the
#          core system pods are Running.
#
# Usage:
#   ./check-cluster.sh
#
# Exit code 0 if healthy, 1 otherwise.

set -euo pipefail

echo "== Tooling =="
kubectl version --client --output=yaml | grep -E 'gitVersion' | head -n1 || true

echo
echo "== API Server reachability =="
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: cannot reach the API server. Check context with: kubectl config current-context" >&2
  exit 1
fi
kubectl cluster-info | head -n1

echo
echo "== Nodes =="
kubectl get nodes -o wide

NOT_READY=$(kubectl get nodes --no-headers | awk '{print $2}' | grep -cv Ready)
if [ "${NOT_READY}" -ne 0 ]; then
  echo "ERROR: ${NOT_READY} node(s) are not Ready." >&2
  exit 1
fi

echo
echo "== Core system pods =="
kubectl get pods -n kube-system -o wide

echo
echo "== Metrics API (for kubectl top and HPA) =="
if kubectl get --raw /apis/metrics.k8s.io/v1beta1 >/dev/null 2>&1; then
  echo "metrics API available"
else
  echo "WARNING: metrics API not available. Install metrics-server for kubectl top and HPA labs."
fi

echo
echo "Cluster health check complete."
