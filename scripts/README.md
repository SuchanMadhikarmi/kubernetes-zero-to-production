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

## Planned Scripts

| File | Purpose |
|------|---------|
| setup-kind.sh | Create a kind cluster for labs |
| setup-minikube.sh | Create a minikube cluster for labs |
| check-cluster.sh | Verify cluster health and tooling |
| cleanup.sh | Remove resources created by labs |

[Back to Repository Home](../README.md)
