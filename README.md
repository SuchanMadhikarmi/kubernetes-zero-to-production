# Kubernetes Zero to Production

![lessons](https://img.shields.io/badge/lessons-47-blue) ![modules](https://img.shields.io/badge/modules-14-brightgreen) ![labs](https://img.shields.io/badge/labs-35-orange) ![license](https://img.shields.io/badge/license-Apache%202.0-blue)

A production-oriented, end-to-end Kubernetes learning repository. It takes you from absolute beginner to production-ready operator through **47 sequential lessons**, **35 hands-on labs**, and a complete ecosystem of manifests, diagrams, cheat sheets, revision notes, and interview guides built around one consistent structure.

> If you learn better by doing, start here. If you are preparing for an interview or a certification, this repository is built for you too. Everything follows the same template, so nothing surprises you.

## Table of Contents

- [Overview](#overview)
- [Why This Repository](#why-this-repository)
- [What Is Inside](#what-is-inside)
- [Navigating the Repository](#navigating-the-repository)
- [The Curriculum at a Glance](#the-curriculum-at-a-glance)
- [How to Get the Most Out of It](#how-to-get-the-most-out-of-it)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [The Lesson Workflow](#the-lesson-workflow)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [Useful Resources](#useful-resources)
- [FAQ](#faq)
- [License](#license)

---

## Overview

Kubernetes documentation is spread across hundreds of pages, and most tutorials stop at "it works" without ever covering production reality. This repository closes that gap.

It is a single, structured path that pairs deep explanations with real practice:

- A **curriculum of 47 lessons** organized into **14 modules**, each written to one consistent template.
- Every hands-on topic has a **matching lab** with exact commands and expected output.
- Ready-to-use **manifests**, **diagrams**, **cheat sheets**, **revision notes**, and **interview questions** support every module.

You can use it as a **learning path**, a **reference handbook**, a **troubleshooting guide**, an **interview preparation kit**, or a **certification study guide**.

## Why This Repository

Most Kubernetes content shares one of two problems: it is either so shallow that it stops at the basics, or so scattered that a beginner cannot find a path. This repository solves both:

- **Sequenced and progressive** - each module depends on the previous one, so concepts are introduced in the order you need them.
- **Production-minded** - every lesson covers the difference between "will run" and "safe in production".
- **Uniform** - one lesson template across all 47 lessons, so once you learn the structure you can skim any topic.
- **Practice-first** - labs, manifests, and scripts are part of the core, not an afterthought.
- **Interview- and exam-ready** - dedicated interview guides and exam-focused lessons (CKA, CKAD, CKS).

## What Is Inside

| Area | Count | Directory |
|------|-------|-----------|
| Lessons | 47 | [docs/](docs/README.md) |
| Curriculum modules | 14 | [docs/](docs/README.md) |
| Hands-on labs | 35 | [labs/](labs/README.md) |
| Kubernetes manifests | 20 | [manifests/](manifests/README.md) |
| Architecture diagrams | 6 | [diagrams/](diagrams/README.md) |
| Static assets | 2 | [assets/](assets/README.md) |
| Cheat sheets | 13 | [cheatsheets/](cheatsheets/README.md) |
| Revision notes | 13 | [revision/](revision/README.md) |
| Interview guides | 12 | [interview/](interview/README.md) |
| Helper scripts | 4 | [scripts/](scripts/README.md) |

## Navigating the Repository

Learn where everything lives, what it is for, and when to open it.

| Path | What It Holds | When To Use It |
|------|---------------|----------------|
| [docs/](docs/README.md) | The full 47-lesson curriculum, organized into 14 numbered modules. Each module README is a topics list with links to every lesson. | Your main study path. Always start here. |
| [docs/README.md](docs/README.md) | The documentation hub - a list of all 14 modules. | Land you to jump to a specific module or to review the whole plan. |
| [labs/](labs/README.md) | Step-by-step lab exercises with commands and expected output. | After reading a hands-on lesson, practise here. |
| [manifests/](manifests/README.md) | Ready-to-use Kubernetes YAML, ordered by module. | Copy, adapt, and verify while following a lesson or lab. |
| [diagrams/](diagrams/README.md) | Larger reusable ASCII architecture diagrams. | When a picture is worth a thousand commands. |
| [assets/](assets/README.md) | Reusable SVG images for documentation. | Embedding visuals in your own notes or slides. |
| [cheatsheets/](cheatsheets/README.md) | Quick one-page references (kubectl, YAML, networking, security, and more). | During labs, at your desk, or before an interview. |
| [revision/](revision/README.md) | Condensed per-module revision notes. | Fast re-reading before an interview or exam. |
| [interview/](interview/README.md) | Topic-wise interview questions and answers. | Interview preparation, role by role. |
| [scripts/](scripts/README.md) | Helper automation for cluster setup, checks, and cleanup. | Getting a local cluster running in minutes. |
| [ROADMAP.md](ROADMAP.md) | Delivery plan, phases, and milestones. | Understanding how the project was built. |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Standards for contributing, formatting, and review. | Before you open a pull request. |

Every directory has its own README, so you can drop into any folder and find its index and conventions immediately.

## The Curriculum at a Glance

The 47 lessons are grouped into four progressive stages.

| Stage | Focus | Modules |
|-------|-------|---------|
| 1. Foundation | Core concepts, architecture, kubectl | 01-02 |
| 2. Core Engineering | Workloads, networking, storage, configuration | 03-06 |
| 3. Security and Operations | Security, observability, packaging, GitOps, operators | 07-11 |
| 4. Production and Beyond | Production hardening, troubleshooting, certifications | 12-14 |

| Module | Lessons | Focus | Status |
|--------|---------|-------|--------|
| [01 Fundamentals](docs/01-fundamentals/README.md) | 1, 23 | Kubernetes basics and kubectl | Complete |
| [02 Architecture](docs/02-architecture/README.md) | 7, 17, 25 | Control plane and worker node internals | Complete |
| [03 Workloads](docs/03-workloads/README.md) | 10-15, 22, 38 | Pods, Deployments, StatefulSets and more | Complete |
| [04 Networking](docs/04-networking/README.md) | 16-19, 33, 37 | Networking, Services, Ingress, Network Policies | Complete |
| [05 Storage](docs/05-storage/README.md) | 20 | Volumes, Persistent Volumes, Storage Classes | Complete |
| [06 Configuration](docs/06-configuration/README.md) | 23, 25 | ConfigMaps, Secrets, resource management | Complete |
| [07 Security](docs/07-security/README.md) | 27, 31 | Authentication, RBAC, Pod Security Standards | Complete |
| [08 Observability](docs/08-observability/README.md) | 30-32, 43-44 | Monitoring, logging, probes | Complete |
| [09 Packaging](docs/09-packaging/README.md) | 33, 39 | Helm and packaging | Complete |
| [10 GitOps](docs/10-gitops/README.md) | 35, 45 | GitOps principles, Argo CD pipelines | Complete |
| [11 Operators](docs/11-operators/README.md) | 32, 34 | CRDs and the Operator pattern | Complete |
| [12 Production](docs/12-production/README.md) | 24, 26, 28, 35-36, 46 | Autoscaling, HA, hardening, capacity, delivery | Complete |
| [13 Troubleshooting](docs/13-troubleshooting/README.md) | 27, 29 | Workload, node, and network debugging | Complete |
| [14 Certifications](docs/14-certifications/README.md) | 40-42, 47 | CKA, CKAD, CKS exam preparation and capstone | Complete |

## How to Get the Most Out of It

Read this repository the way you study, but tailor it to your goal.

### Beginner path: follow the modules in order

For a beginner, follow the curriculum in order in `docs/`. The modules are intentionally sequenced, and each depends on the ones before it.

Open the module README, then open the lesson, then run the lab.

### For interview preparation

1. Skim each module's lesson quickly.
2. Drill the questions in [interview/](interview/README.md) - one file per topic.
3. Refresh the underlined points in [revision/](revision/README.md).
4. Review the one-page visuals in [cheatsheets/](cheatsheets/README.md) the morning of the interview.

### For exam preparation (CKA, CKAD, CKS)

1. Follow the curriculum in order through [14 Certifications](docs/14-certifications/README.md).
2. Re-take the exam masterclass lessons and the attached labs.
3. Practice the scenario-style questions to match exam conditions.

### For active engineering and troubleshooting

Jump straight to the topic that matches your problem:

- A behaviour or rollout issue? See [Troubleshooting](docs/13-troubleshooting/README.md) and [revision/troubleshooting](./revision/troubleshooting.md).
- A networking problem? See [04-networking](docs/04-networking/README.md) and the service/ingress diagrams.
- A resource problem (CPU, memory, OOMKill)? See [06-configuration](docs/06-configuration/README.md).

### Portfolio and mentorship

Use the production-oriented labs (e.g., the 3-tier application, GitOps pipelines, the final capstone) to build real, presentable pieces of portfolio work.

## Quick Start

```bash
git clone https://github.com/SuchanMadhikarmi/kubernetes-zero-to-production.git
cd kubernetes-zero-to-production
```

Then open the documentation hub to find your starting module:

[Read the Documentation](docs/README.md)

If you have a cluster, you can be running in a few minutes:

```bash
./scripts/check-cluster.sh
```

If you do not have a cluster yet, see [Prerequisites](#prerequisites) for a two-line setup.

## Prerequisites

No Kubernetes knowledge is required to start. The following make the journey smoother:

- Basic command-line (terminal) familiarity
- Basic YAML and JSON understanding
- Linux command-line familiarity (helpful, not required)
- Container or Docker basics (optional, covered again in the fundamentals)

For hands-on labs you need one local environment. Use the bundled scripts for the fastest start:

- [kind](https://kind.sigs.k8s.io/) - Kubernetes in Docker, simplest to start
- [minikube](https://minikube.sigs.k8s.io/docs/) - local single-node cluster
- [k3s](https://k3s.io/) - lightweight Kubernetes
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) - bundled Kubernetes
- A managed cloud cluster (EKS, AKS, GKE) if you have one

```bash
# kind (recommended)
./scripts/setup-kind.sh

# or minikube
./scripts/setup-minikube.sh docker 4 8192

# verify setup
./scripts/check-cluster.sh
```

See [scripts/README.md](scripts/README.md) for full usage. Clean up lab resources with [cleanup.sh](scripts/cleanup.sh).

## The Lesson Workflow

Every lesson follows one consistent template, so the moment you learn the structure you can move quickly through any topic. Each lesson includes a table of contents, learning objectives, prerequisites, real-world motivation, core concepts, architecture, ASCII diagrams, hands-on exercises, commands, YAML explanations, production notes, best practices, common mistakes, troubleshooting, interview questions, scenarios, a quiz, revision, cheat sheet, references, and related lessons.

The loop the repository encourages:

```text
Read a lesson        (docs/NN-module/lesson-NN-*.md)
      |
      v
Do the lab            (labs/lab-NN-*.md)
      |
      v
Inspect/adapt manifests (manifests/NN-*/)
      |
      v
Revise                (revision/ + cheatsheets/)
      |
      v
Verify your knowledge (interview/)
```

## Roadmap

The repository is fully delivered. See [ROADMAP.md](ROADMAP.md) for the phases, milestones, and delivery history.

## Contributing

Contributions, corrections, and improvements are welcome. Before opening a pull request, read [CONTRIBUTING.md](CONTRIBUTING.md) to understand the lesson template, formatting standards, and review process. Every lesson follows one template, and every lesson requires a matching support file where relevant.

## Useful Resources

- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [CNCF Cloud Native Landscape](https://landscape.cncf.io/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Kubernetes GitHub Repository](https://github.com/kubernetes/kubernetes)
- [CKA Exam Curriculum](https://github.com/cncf/curriculum)
- [Kubernetes Concepts](https://kubernetes.io/docs/concepts/)

## FAQ

**Do I need a cluster to start?**
No. You can read the entire curriculum without a cluster. You only need one for the labs, and a two-command setup via the scripts.

**Should I read every lesson?**
Not necessarily. Follow the [pathways](#how-to-get-the-most-out-of-it) to focus on what matches your goal, and pivot labs around your interests.

**Is this a replacement for the official docs?**
No. It is a structured path through the official ecosystem. Keep the official documentation as the source of truth for the latest detail.

**What Kubernetes versions are covered?**
The repository targets modern, current K8s releases and covers the terms every operator needs.

## License

This repository is licensed under [Apache License 2.0](LICENSE). See [LICENSE](LICENSE) for details.
