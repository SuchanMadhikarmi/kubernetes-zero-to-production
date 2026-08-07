#!/usr/bin/env bash
#
# cleanup.sh
#
# Purpose: Remove resources created by the labs in a safe, targeted way.
#          By default it deletes the resources created across the curriculum
#          (namespaces, deployments, services, and test artifacts). It never
#          touches kube-system or the control plane.
#
# Usage:
#   ./cleanup.sh [--all]
#     --all   also delete the kind/minikube cluster
#
# Safe to run repeatedly.

set -euo pipefail

ALL="${1:-}"

echo "Deleting lab namespaces..."
for ns in lab default-apps demo gitops argocd argo-rollouts monitoring; do
  if kubectl get namespace "${ns}" >/dev/null 2>&1; then
    kubectl delete namespace "${ns}" --ignore-not-found >/dev/null 2>&1 || true
  fi
done

echo "Deleting leftover lab objects in the default namespace..."
kubectl delete deployment,rs,statefulset,daemonset,job,cronjob \
  -l 'lab=k8s-zero-to-hero' --ignore-not-found >/dev/null 2>&1 || true
kubectl delete service,ingress,configmap,secret,pvc --all \
  -n default --ignore-not-found >/dev/null 2>&1 || true

echo "Removing taints and node labels created by scheduling labs..."
for node in $(kubectl get nodes -o name 2>/dev/null || true); do
  kubectl taint nodes "${node#node/}" key=value:NoSchedule- >/dev/null 2>&1 || true
  kubectl label nodes "${node#node/}" disktype- >/dev/null 2>&1 || true
done

if [ "${ALL}" = "--all" ]; then
  echo "Deleting the local kind/minikube cluster..."
  if command -v kind >/dev/null 2>&1; then
    kind delete cluster --name k8s-zero-to-hero >/dev/null 2>&1 || true
  fi
  if command -v minikube >/dev/null 2>&1; then
    minikube delete --purge >/dev/null 2>&1 || true
  fi
fi

echo "Cleanup complete."
