---
title: Interview - GitOps and Packaging
module: Modules 09-11
status: Complete
tags: [interview, gitops, argocd, helm, kustomize, operators]
---

# Interview - GitOps and Packaging

## Beginner

**Q: What is GitOps?**

A: An operating model where Git is the single source of truth for desired state. A controller (ArgoCD) continuously reconciles the cluster to what is in Git, making deployments declarative and reversible.

**Q: What is a Helm chart?**

A: A packaged set of Kubernetes manifests, using Go templates and values, so one chart can deploy an app with different values per environment.

## Intermediate

**Q: How does ArgoCD detect drift?**

A: It continuously polls Git and compares it to live cluster state. A manual `kubectl edit` makes the app "Out of Sync"; with `selfHeal`, ArgoCD patches it back to the Git state. `--auto-prune` removes resources deleted from Git.

**Q: What is the difference between Helm and Kustomize?**

A: Helm is templating with values and releases (install/upgrade/rollback, third-party charts). Kustomize is a patches/overlay tool with no templating, built into kubectl, adding/merging labels, names, and images over a base.

**Q: What is a CRD?**

A: A CustomResourceDefinition extends the Kubernetes API with a new resource type. The Operator pattern pairs it with a custom controller that reconciles the resource toward desired state (e.g., Prometheus Operator, Argo Rollouts).

## Advanced

Q: How do ArgoCD and Argo Rollouts work together?

A: ArgoCD syncs the Rollout manifest from Git to the cluster; the Argo Rollouts controller runs the canary steps and traffic shifts. ArgoCD reports sync/health; the Rollouts controller gates the rollout with an AnalysisTemplate.

## Scenario

Q: Helm upgrade broke your app. How to recover quickly?

A: Roll back with `helm rollback <release> <revision>`, then reproduce the issue from `helm diff`/values before re-releasing. In a GitOps setup, `git revert` the change and let ArgoCD reconcile.

## Related

- [Revision - Packaging and GitOps](../revision/packaging-gitops.md)
- [Revision - Operators](../revision/operators.md)

[Back to Interview Index](README.md)