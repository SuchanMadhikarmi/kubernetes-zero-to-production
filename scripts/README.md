# Scripts

Reusable helper scripts and automation.

## Purpose

Scripts that make learning faster: cluster setup, environment checks, cleanup, and small utilities referenced by the lessons.

## Conventions

- File naming: `kebab-case-name.sh`
- Every script includes a header comment describing its purpose and usage
- Scripts are idempotent where possible
- Scripts must not require credentials to be stored in the repository
- Shell scripts use `set -euo pipefail`

## Scripts

All scripts use `set -euo pipefail`, are idempotent, and store no credentials.

| File | Purpose |
|------|---------|
| [setup-kind.sh](setup-kind.sh) | Create a kind cluster for labs (default `k8s-zero-to-hero`) |
| [setup-minikube.sh](setup-minikube.sh) | Create a minikube cluster and enable metrics-server |
| [check-cluster.sh](check-cluster.sh) | Verify cluster health and tooling readiness |
| [cleanup.sh](cleanup.sh) | Remove lab resources; `--all` also deletes the cluster |

Usage:

```bash
./scripts/setup-kind.sh
./scripts/setup-minikube.sh docker 4 8192
./scripts/check-cluster.sh
./scripts/cleanup.sh --all
```

[Back to Repository Home](../README.md)
