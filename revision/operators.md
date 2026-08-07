---
title: Revision - Operators
module: 11 Operators
status: Complete
tags: [revision, operators, crd, custom-resources, operator-pattern]
---

# Revision - Operators

## Core Ideas

- **CRDs** (CustomResourceDefinitions) extend the Kubernetes API with new resource types.
- The **Operator pattern**: a custom controller watches a CRD and reconciles actual state toward the desired state, encoding application-specific operational knowledge (backups, upgrades, scaling).
- Controllers run the same reconciliation loop as built-in controllers (watch, diff, act).

## Building Blocks

- `CustomResourceDefinition` - defines the API (schema, scope).
- Custom resource instances - your declarative desired state.
- A controller (usually written in Go, using client-go/controller-runtime) - the logic.
- RBAC for the controller to manage the custom resources.

## Examples

- Prometheus Operator (ServiceMonitor CRDs)
- Argo Rollouts (Rollout + AnalysisTemplate CRDs)
- PostgreSQL/MySQL operators (databases)
- Cert-Manager (Certificate CRDs)

## Quick Facts

| Fact | Value |
|------|-------|
| CRD API group | e.g. `example.com/v1` |
| Cluster vs namespaced | set in `spec.scope` |
| Controller language | Go (client-go, controller-runtime) |

## Related Lessons

- [Lesson 32 - Extending Kubernetes with CRDs and Operators](../docs/11-operators/lesson-32-extending-kubernetes-crds-and-operators.md)
- [Lesson 34 - Operators in Practice](../docs/11-operators/lesson-34-operators-in-practice.md)

## Related Material

- [Interview - GitOps](../interview/gitops.md)

[Back to Revision Index](README.md)