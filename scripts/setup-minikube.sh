#!/usr/bin/env bash
#
# setup-minikube.sh
#
# Purpose: Create a minikube cluster suitable for running the labs in this
#          repository. Uses the docker driver by default and enables the
#          metrics-server addon so HPA lessons work.
#
# Usage:
#   ./setup-minikube.sh [driver] [cpus] [memory-mb]
#   ./setup-minikube.sh docker 4 8192
#
# Idempotent: if the cluster is already running, it reports and exits.

set -euo pipefail

DRIVER="${1:-docker}"
CPUS="${2:-4}"
MEMORY="${3:-8192}"

if ! command -v minikube >/dev/null 2>&1; then
  echo "ERROR: 'minikube' is not installed. Install it first: https://minikube.sigs.k8s.io/docs/start/" >&2
  exit 1
fi

if minikube status >/dev/null 2>&1; then
  echo "minikube cluster already running:"
  minikube status
  exit 0
fi

echo "Starting minikube (driver=${DRIVER}, cpus=${CPUS}, memory=${MEMORY}Mi)..."
minikube start --driver="${DRIVER}" --cpus="${CPUS}" --memory="${MEMORY}"

echo "Enabling the metrics-server addon (required for kubectl top and HPA)..."
minikube addons enable metrics-server

echo
echo "Cluster ready. Verify with:"
echo "  kubectl cluster-info"
echo "  kubectl get nodes"
echo "  kubectl top nodes"
