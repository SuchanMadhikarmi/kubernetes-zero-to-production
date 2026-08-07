---
title: Revision - Fundamentals
module: 01 Fundamentals
status: Complete
tags: [revision, fundamentals, containers, namespaces, cgroups, kubectl]
---

# Revision - Fundamentals

## Core Ideas

- Kubernetes is a platform for running and orchestrating containers at scale. It is declarative: you describe desired state, controllers drive reality toward it.
- A **container** is a Linux process isolated by **namespaces** (filesystem, PID, network, mount, UTS, IPC, user) and constrained by **cgroups** (CPU, memory, I/O).
- Kubernetes hides the container runtime behind the **CRI**; a Pod wraps one or more containers sharing a network namespace and IP.
- `kubectl` is the CLI. It talks to the API Server using a kubeconfig with context, cluster, and user.

## Key Commands

```bash
kubectl config get-contexts / current-context / use-context <name>
kubectl config set-context --current --namespace=<ns>
kubectl create namespace <ns>
kubectl get nodes
kubectl get pods -A
kubectl describe pod <name>
kubectl logs <pod> --previous
kubectl apply -f file.yaml
kubectl delete -f file.yaml
kubectl run nginx --image=nginx --dry-run=client -o yaml
kubectl explain pod.spec
kubectl cluster-info
kubectl api-resources
```

## Quick Facts

| Fact | Value |
|------|-------|
| Smallest deployable unit | Pod |
| Default Pod restartPolicy | Always |
| Control plane port for API Server | 6443 |
| etcd port | 2379 |
| Default service account namespace | default |
| Current context shortcut | `kubectl config current-context` |

## Namespaces vs cgroups (30 seconds)

- **Namespaces** isolate what a process can *see* (processes, network, filesystem).
- **cgroups** limit what it can *use* (CPU, memory, I/O).

## Related Lessons

- [Lesson 01 - Anatomy of a Container](../docs/01-fundamentals/lesson-01-anatomy-of-a-container.md)
- [Lesson 23 - Namespaces and Contexts](../docs/01-fundamentals/lesson-23-namespaces-and-contexts.md)

## Related Material

- [kubectl Cheat Sheet](../cheatsheets/kubectl-cheatsheet.md)
- [Interview - Fundamentals](../interview/fundamentals.md)

[Back to Revision Index](README.md)