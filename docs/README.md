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
| [01 Fundamentals](01-fundamentals/README.md) | 1-5 | Kubernetes basics and kubectl | In Progress (2/5) |
| [02 Architecture](02-architecture/README.md) | 7, 17, 25, 6, 8, 9 | Control plane and worker node internals | In Progress (3/6) |
| [03 Workloads](03-workloads/README.md) | 10-15 | Pods, Deployments, StatefulSets and more | Complete (6/6) |
| [04 Networking](04-networking/README.md) | 16-19, 33 | Networking, Services, Ingress, Network Policies | Complete (5/5) |
| [05 Storage](05-storage/README.md) | 20-22 | Volumes, Persistent Volumes, Storage Classes | In Progress (1/3) |
| [06 Configuration](06-configuration/README.md) | 23-25 | ConfigMaps, Secrets, resource management | Complete (3/3) |
| [07 Security](07-security/README.md) | 26-29, 31 | Authentication, RBAC, Pod Security Standards | In Progress (2/5) |
| [08 Observability](08-observability/README.md) | 30-32 | Monitoring, logging, probes | Complete (3/3) |
| [09 Packaging](09-packaging/README.md) | 33-34 | Helm and Kustomize | In Progress (1/2) |
| [10 GitOps](10-gitops/README.md) | 35-36 | GitOps principles, Argo CD, Flux | In Progress (1/2) |
| [11 Operators](11-operators/README.md) | 32, 34, 37-38 | CRDs and the Operator pattern | In Progress (2/3) |
| [12 Production](12-production/README.md) | 24, 26, 28, 39-42 | Autoscaling, HA, hardening, capacity | In Progress (3/6) |
| [13 Troubleshooting](13-troubleshooting/README.md) | 27, 29, 43-44 | Workload, node, and network debugging | In Progress (2/3) |
| [14 Certifications](14-certifications/README.md) | 45-47 | CKA, CKAD, CKS exam preparation | Planned |

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
| Fundamentals | [README](01-fundamentals/README.md) | 1-5 | In Progress |
| Architecture | [README](02-architecture/README.md) | 6-9 | Planned |
| Workloads | [README](03-workloads/README.md) | 10-15 | In Progress |
| Networking | [README](04-networking/README.md) | 16-19 | Planned |
| Storage | [README](05-storage/README.md) | 20-22 | Planned |
| Configuration | [README](06-configuration/README.md) | 23-25 | Planned |
| Security | [README](07-security/README.md) | 26-29 | In Progress |
| Observability | [README](08-observability/README.md) | 30-32 | Planned |
| Packaging | [README](09-packaging/README.md) | 33-34 | Planned |
| GitOps | [README](10-gitops/README.md) | 35-36 | Planned |
| Operators | [README](11-operators/README.md) | 37-38 | Planned |
| Production | [README](12-production/README.md) | 39-42 | Planned |
| Troubleshooting | [README](13-troubleshooting/README.md) | 43-44 | Planned |
| Certifications | [README](14-certifications/README.md) | 45-47 | Planned |

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
