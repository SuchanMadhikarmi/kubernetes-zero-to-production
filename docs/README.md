# Documentation Hub

This is the navigation center for the full 47-lesson Kubernetes curriculum.

## Table of Contents

- [Curriculum Map](#curriculum-map)
- [How to Use This Repository](#how-to-use-this-repository)
- [Lesson Template](#lesson-template)
- [Module Index](#module-index)
- [Supporting Material](#supporting-material)
- [Status Legend](#status-legend)

---

## Curriculum Map

The curriculum is organized into 14 modules. Each module contains a set of sequential lessons.

| Module | Lessons | Focus | Status |
|--------|---------|-------|--------|
| [01 Fundamentals](01-fundamentals/README.md) | 1, 23 | Kubernetes basics and kubectl | Complete (2/2) |
| [02 Architecture](02-architecture/README.md) | 7, 17, 25 | Control plane and worker node internals | Complete (3/3) |
| [03 Workloads](03-workloads/README.md) | 10-15, 22, 38 | Pods, Deployments, StatefulSets and more | Complete (7/7) |
| [04 Networking](04-networking/README.md) | 16-19, 33, 37 | Networking, Services, Ingress, Network Policies | Complete (6/6) |
| [05 Storage](05-storage/README.md) | 20 | Volumes, Persistent Volumes, Storage Classes | Complete (1/1) |
| [06 Configuration](06-configuration/README.md) | 23, 25 | ConfigMaps, Secrets, resource management | Complete (2/2) |
| [07 Security](07-security/README.md) | 27, 31 | Authentication, RBAC, Pod Security Standards | Complete (2/2) |
| [08 Observability](08-observability/README.md) | 30-32, 43-44 | Monitoring, logging, probes | Complete (5/5) |
| [09 Packaging](09-packaging/README.md) | 33, 39 | Helm and Kustomize | Complete (2/2) |
| [10 GitOps](10-gitops/README.md) | 35, 45 | GitOps principles, Argo CD, Flux | Complete (2/2) |
| [11 Operators](11-operators/README.md) | 32, 34 | CRDs and the Operator pattern | Complete (2/2) |
| [12 Production](12-production/README.md) | 24, 26, 28, 35-36, 46 | Autoscaling, HA, hardening, capacity | Complete (6/6) |
| [13 Troubleshooting](13-troubleshooting/README.md) | 27, 29 | Workload, node, and network debugging | Complete (2/2) |
| [14 Certifications](14-certifications/README.md) | 40-42, 47 | CKA, CKAD, CKS exam preparation | Complete (4/4) |

## How to Use This Repository

- Start with `01-fundamentals` and follow the modules in order.
- Each module page lists its lessons, learning outcomes, and dependencies.
- When a lesson is published, it appears as a link in its module index.
- Hands-on lessons point to labs in the top-level `labs/` directory.
- Manifests referenced by lessons live in the top-level `manifests/` directory.
- Use `revision/` and `cheatsheets/` for quick review after completing a module.

## Lesson Template

Every lesson follows one consistent template so the learning experience is uniform across the curriculum. The template defines 22 required sections.

See [lesson-template.md](_templates/lesson-template.md) for the full structure.

## Module Index

| Module | Lessons | Lesson Range | Status |
|--------|---------|--------------|--------|
| Fundamentals | [README](01-fundamentals/README.md) | 1, 23 | Complete |
| Architecture | [README](02-architecture/README.md) | 7, 17, 25 | Complete |
| Workloads | [README](03-workloads/README.md) | 10-15, 22, 38 | Complete |
| Networking | [README](04-networking/README.md) | 16-19, 33, 37 | Complete |
| Storage | [README](05-storage/README.md) | 20 | Complete |
| Configuration | [README](06-configuration/README.md) | 23, 25 | Complete |
| Security | [README](07-security/README.md) | 27, 31 | Complete |
| Observability | [README](08-observability/README.md) | 30-32, 43-44 | Complete |
| Packaging | [README](09-packaging/README.md) | 33, 39 | Complete |
| GitOps | [README](10-gitops/README.md) | 35, 45 | Complete |
| Operators | [README](11-operators/README.md) | 32, 34 | Complete |
| Production | [README](12-production/README.md) | 24, 26, 28, 35-36, 46 | Complete |
| Troubleshooting | [README](13-troubleshooting/README.md) | 27, 29 | Complete |
| Certifications | [README](14-certifications/README.md) | 40-42, 47 | Complete |

## Supporting Material

| Directory | Purpose |
|-----------|---------|
| [labs/](../labs/README.md) | Hands-on lab exercises |
| [manifests/](../manifests/README.md) | Ready-to-use YAML manifests |
| [diagrams/](../diagrams/README.md) | Architecture and concept diagrams |
| [assets/](../assets/README.md) | Images and static resources |
| [interview/](../interview/README.md) | Interview questions by topic |
| [revision/](../revision/README.md) | Condensed revision notes |
| [cheatsheets/](../cheatsheets/README.md) | Quick-reference cheat sheets |
| [scripts/](../scripts/README.md) | Reusable helper scripts |

## Status Legend

- `Planned` - not started
- `In Progress` - actively being worked on
- `Complete` - finished and verified

[Back to top](#documentation-hub)
