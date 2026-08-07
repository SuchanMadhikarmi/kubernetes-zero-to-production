# Diagrams

Architecture and concept diagrams for the lessons.

## Purpose

Visual explanations of Kubernetes components, flows, and topologies. Diagrams live as ASCII art inside lessons and as standalone files here for larger or reusable visuals.

## Conventions

- File naming: `topic-name.txt` for ASCII diagrams, `topic-name.svg` for image diagrams
- Organize by module
- ASCII diagrams use monospace-safe box drawing characters that render on GitHub
- Every diagram explains the module and lesson it belongs to

## Diagrams

Standalone ASCII diagrams for larger or reusable visuals. Organized by topic; each is also embedded (or linked) from the relevant lesson.

| File | Covers |
|------|--------|
| [control-plane-architecture.txt](control-plane-architecture.txt) | Control plane and worker node components |
| [request-flow.txt](request-flow.txt) | Data path from kubectl to a Pod, and external traffic flow |
| [deployment-rollout.txt](deployment-rollout.txt) | Rolling update, rollback, pause, history |
| [service-and-ingress.txt](service-and-ingress.txt) | Service selectors, Endpoints, Ingress routing |
| [storage-provisioning.txt](storage-provisioning.txt) | PV/PVC/StorageClass dynamic provisioning lifecycle |
| [gitops-argocd.txt](gitops-argocd.txt) | ArgoCD GitOps pull model and drift reconciliation |

## ASCII Example

```text
+---------------------+
|   Control Plane     |
+---------------------+
        |
        v
+---------------------+
|   Worker Node       |
+---------------------+
```

[Back to Repository Home](../README.md)
