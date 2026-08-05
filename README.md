# Kubernetes Zero to Production

A structured, production-oriented Kubernetes learning repository built around 47 sequential lessons that take you from absolute beginner to production-ready operator.

## Table of Contents

- [Repository Overview](#repository-overview)
- [Why This Repository](#why-this-repository)
- [Repository Goals](#repository-goals)
- [Learning Roadmap](#learning-roadmap)
- [Progress Tracker](#progress-tracker)
- [Folder Map](#folder-map)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Recommended Learning Order](#recommended-learning-order)
- [Contribution Guide](#contribution-guide)
- [Useful Resources](#useful-resources)
- [License](#license)

---

## Repository Overview

This repository is a complete Kubernetes learning path that combines:

- Deep, easy-to-follow documentation
- Hands-on labs and manifests
- Interview and certification preparation
- Revision notes and cheat sheets
- Production best practices and troubleshooting guides

Every lesson follows a single, consistent template so the learning experience is uniform across the entire curriculum. The material is suitable for beginners, working engineers, interview preparation, and portfolio showcase.

## Why This Repository

Kubernetes documentation is comprehensive but spread across hundreds of pages. Most tutorials stop at "it works" and never cover production reality. This repository bridges that gap by delivering a single, structured path that covers:

- Core concepts and architecture
- Hands-on practice with real manifests
- Production hardening and operational knowledge
- Interview, certification, and revision material

## Repository Goals

This repository is designed to serve as:

- Kubernetes Handbook
- Kubernetes Interview Guide
- Kubernetes Revision Notes
- Kubernetes Production Guide
- Kubernetes Labs
- Kubernetes Troubleshooting Guide
- Kubernetes Cheat Sheets
- Kubernetes Architecture Guide
- Kubernetes Best Practices Guide

## Learning Roadmap

The curriculum is delivered in four progressive stages. Each stage builds on the previous one.

| Stage | Focus | Modules | Outcome |
|-------|-------|---------|---------|
| 1. Foundation | Core concepts, architecture, and kubectl | 01-02 | Understand how Kubernetes works |
| 2. Core Engineering | Workloads, networking, storage, configuration | 03-06 | Run and configure real applications |
| 3. Security and Operations | Security, observability, packaging, GitOps, operators | 07-11 | Operate clusters like a professional |
| 4. Production and Beyond | Production hardening, troubleshooting, certifications | 12-14 | Prepare for production and exams |

See the [ROADMAP](ROADMAP.md) for the full delivery plan and milestones.

## Progress Tracker

All 47 lessons are defined. Each lesson file is created and marked complete as content is published.

| Module | Lessons | Focus | Status |
|--------|---------|-------|--------|
| [01 Fundamentals](docs/01-fundamentals/README.md) | 1-5 | Kubernetes basics and kubectl | In Progress |
| [02 Architecture](docs/02-architecture/README.md) | 6-9 | Control plane and worker node internals | In Progress (1/4) |
| [03 Workloads](docs/03-workloads/README.md) | 10-15 | Pods, Deployments, StatefulSets and more | In Progress (4/6) |
| [04 Networking](docs/04-networking/README.md) | 16-19 | Networking, Services, Ingress, Network Policies | In Progress (2/4) |
| [05 Storage](docs/05-storage/README.md) | 20-22 | Volumes, Persistent Volumes, Storage Classes | In Progress (1/3) |
| [06 Configuration](docs/06-configuration/README.md) | 23-25 | ConfigMaps, Secrets, resource management | Complete (3/3) |
| [07 Security](docs/07-security/README.md) | 26-29 | AuthN/AuthZ, RBAC, Pod Security Standards | In Progress (1/4) |
| [08 Observability](docs/08-observability/README.md) | 30-32 | Monitoring, logging, probes | Planned |
| [09 Packaging](docs/09-packaging/README.md) | 33-34 | Helm and Kustomize | Planned |
| [10 GitOps](docs/10-gitops/README.md) | 35-36 | GitOps principles, Argo CD, Flux | Planned |
| [11 Operators](docs/11-operators/README.md) | 37-38 | CRDs and the Operator pattern | Planned |
| [12 Production](docs/12-production/README.md) | 39-42 | Autoscaling, HA, hardening, capacity | Planned |
| [13 Troubleshooting](docs/13-troubleshooting/README.md) | 43-44 | Workload, node, and network debugging | Planned |
| [14 Certifications](docs/14-certifications/README.md) | 45-47 | CKA, CKAD, CKS exam preparation | Planned |

Status legend: `Planned`, `In Progress`, `Complete`.

## Folder Map

| Path | Purpose |
|------|---------|
| [docs/](docs/README.md) | The 47-lesson curriculum organized into 14 modules |
| [labs/](labs/README.md) | Hands-on lab exercises that accompany lessons |
| [manifests/](manifests/README.md) | Ready-to-use Kubernetes YAML manifests |
| [diagrams/](diagrams/README.md) | Architecture and concept diagrams |
| [assets/](assets/README.md) | Images and static resources used across the repo |
| [interview/](interview/README.md) | Interview questions organized by topic |
| [revision/](revision/README.md) | Condensed revision notes for fast review |
| [cheatsheets/](cheatsheets/README.md) | Quick-reference cheat sheets |
| [scripts/](scripts/README.md) | Reusable helper scripts and automation |
| [ROADMAP.md](ROADMAP.md) | Delivery plan and milestones |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines and standards |

## Quick Start

```bash
# Clone the repository
git clone https://github.com/SuchanMadhikarmi/kubernetes-zero-to-production.git
cd kubernetes-zero-to-production

# Start with the first module
# Recommended reading order: docs/01-fundamentals/README.md
```

For hands-on practice you need access to a Kubernetes cluster. See [Prerequisites](#prerequisites).

## Prerequisites

No Kubernetes knowledge is required to start. A few fundamentals make the journey smoother:

- Basic command-line (terminal) familiarity
- Basic YAML and JSON understanding
- Familiarity with the Linux command line (helpful, not required)
- Docker or container basics (recommended, covered again in Lesson 02)

For hands-on labs you need one local environment:

- [kind](https://kind.sigs.k8s.io/) - Kubernetes in Docker, fastest to start
- [minikube](https://minikube.sigs.k8s.io/docs/) - local single-node cluster
- [k3s](https://k3s.io/) - lightweight Kubernetes distribution
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) - bundled Kubernetes
- A managed cloud cluster (EKS, AKS, GKE) if you have one

## Recommended Learning Order

Work through the modules in numerical order. The curriculum is intentionally sequenced:

1. Complete `01-fundamentals` and `02-architecture` before anything else. They build the mental model.
2. Progress through `03` to `08` in order. Each module depends on concepts from the previous one.
3. `09` to `11` (Helm, GitOps, Operators) assume you are comfortable writing manifests by hand.
4. `12` to `14` are the production and certification capstone.

The `revision/` and `cheatsheets/` directories are designed for re-review after finishing the full path.

## Contribution Guide

Contributions, corrections, and improvements are welcome. Before contributing, read [CONTRIBUTING.md](CONTRIBUTING.md) to understand the lesson template, formatting standards, and review process.

## Useful Resources

- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [CNCF Cloud Native Landscape](https://landscape.cncf.io/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Kubernetes GitHub Repository](https://github.com/kubernetes/kubernetes)
- [CKA Exam Curriculum](https://github.com/cncf/curriculum)
- [Kubernetes Concepts Explained](https://kubernetes.io/docs/concepts/)

## License

This repository is licensed under the [Apache License 2.0](LICENSE).
