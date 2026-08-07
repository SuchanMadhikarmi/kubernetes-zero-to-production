---
title: Revision - Packaging and GitOps
module: Modules 09-10
status: Complete
tags: [revision, helm, kustomize, gitops, argocd, packaging]
---

# Revision - Packaging and GitOps

## Helm

- Helm packages manifests as a **Chart** (Chart.yaml, values.yaml, templates/, charts/).
- Templates use Go templating; values override separately per environment.
- Releases have history and can be upgraded/rolled back.

```bash
helm create mychart
helm install web ./mychart -f values.yaml --set image.tag=v2
helm upgrade web ./mychart --set image.tag=v3
helm history web
helm rollback web <revision>
helm template ./mychart > out.yaml
helm lint ./mychart
```

## Kustomize

- Overlays patch a base with no templating; built into kubectl.

```bash
kubectl kustomize ./overlays/prod
kubectl apply -k ./overlays/prod
kubectl diff -k ./overlays/prod
```

- Elements: `resources`, `patches`, `commonLabels`, `namePrefix`/`nameSuffix`, `images`, `configMapGenerator`.

## GitOps

- Git is the single source of truth; a controller (ArgoCD) reconciles cluster to Git.
- Pull model; drift detection; `selfHeal` reverts manual changes; `prune` removes deleted resources.

```bash
argocd app create web --repo ... --path apps/web --dest-namespace web
argocd app sync web --prune
argocd app diff web
argocd app rollback web <revision>
```

## Related Lessons

- [Lesson 33 - Helm](../docs/09-packaging/lesson-33-helm.md)
- [Lesson 39 - Helm Deep Dive (Writing Production Charts)](../docs/09-packaging/lesson-39-helm-deep-dive-writing-production-charts.md)
- [Lesson 35 - GitOps Principles and Practices](../docs/10-gitops/lesson-35-gitops-principles-and-practices.md)
- [Lesson 45 - CI/CD Pipelines (GitHub Actions + ArgoCD)](../docs/10-gitops/lesson-45-cicd-pipelines-github-actions-and-argocd.md)

## Related Material

- [Packaging Cheat Sheet](../cheatsheets/packaging-cheatsheet.md)
- [GitOps Cheat Sheet](../cheatsheets/gitops-cheatsheet.md)
- [Interview - GitOps](../interview/gitops.md)

[Back to Revision Index](README.md)