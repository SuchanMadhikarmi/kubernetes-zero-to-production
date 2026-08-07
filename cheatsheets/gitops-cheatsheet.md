---
title: GitOps Cheat Sheet (ArgoCD and Argo Rollouts)
topic: gitops
status: Complete
tags: [cheatsheet, gitops, argocd, argo-rollouts, canary, cd]
---

# GitOps Cheat Sheet (ArgoCD and Argo Rollouts)

GitOps: Git is the single source of truth; a controller continuously reconciles the cluster to the desired state in Git. ArgoCD is the CD controller; Argo Rollouts provides progressive delivery (canary/blue-green) with metric analysis.

## ArgoCD principles

- **Desired state in Git**, not imperative `kubectl`.
- **Pull model**: ArgoCD polls Git and applies to the cluster (no CI/CD "push").
- **Drift detection**: manual changes are flagged Out of Sync and (with self-heal) reverted to Git.
- **Sync/App lifecycle**: apps, projects, and repos; sync history and rollbacks.

## ArgoCD install and login

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd -w
kubectl port-forward svc/argocd-server -n argocd 8080:443
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Login from CLI:

```bash
argocd login localhost:8080 --insecure --username admin
argocd account update-password
```

## Manage apps

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: web
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/kubernetes-manifests
    path: apps/web
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: web
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

```bash
argocd app create web --repo https://github.com/myorg/kubernetes-manifests --path apps/web --dest-server https://kubernetes.default.svc --dest-namespace web
argocd app list
argocd app get web
argocd app sync web --prune
argocd app diff web
argocd app rollback web <revision>
argocd app delete web
argocd app set web --sync-policy automated --auto-prune --self-heal
```

Key options:

| Option | Effect |
|--------|--------|
| `--sync-policy automated` | auto-sync on Git changes |
| `--auto-prune` | delete resources removed from Git |
| `--self-heal` | revert manual drift back to Git |
| `--sync-options CreateNamespace=true` | create the destination namespace |
| `--sync-strategy apply` | server-side apply |

## Common ArgoCD resources

- **Application** - the app source/destination/sync policy.
- **AppProject** - scopes which repos/clusters/namespaces an app may use.
- **Repository** (credential) - access to Git repos.
- **Cluster** - registered target clusters.
- **ApplicationSet** (generator) - templated multi-env/multi-cluster apps (git/cluster/list generators).

## Repo vs directory sync

- Kustomize: put a `kustomization.yaml` and set `--kustomize`.
- Helm: reference the chart; ArgoCD runs `helm template` (or Helm-sync with `--helm`).
- Plain YAML: multiple files or a directory path.
- Use `targetRevision` for branch/tag/SHA.

## GitOps best practices

- Do not run imperative `kubectl apply`/`kubectl edit` in prod; let Git drive.
- Separate config repo or directory per app/environment.
- One-way: ArgoCD writes to cluster; don't hand-edit live state.
- `git revert` is the rollback; ArgoCD reconciles automatically.

## Argo Rollouts (progressive delivery)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: web
spec:
  replicas: 4
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginx:1.25-alpine
  strategy:
    canary:
      steps:
      - setWeight: 20
      - pause: {duration: 10s}
      - setWeight: 40
      - pause: {duration: 10s}
      - setWeight: 60
      - pause: {duration: 10s}
      - setWeight: 80
      - pause: {duration: 10s}
```

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
curl -sLO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
kubectl argo rollouts version

kubectl apply -f rollout.yaml
kubectl argo rollouts get rollout web --watch
kubectl argo rollouts set image web web=nginx:1.26
kubectl argo rollouts abort web           # manual failure: canary -> 0, stable takes 100%
kubectl argo rollouts promote web         # skip pauses, fast-forward
kubectl argo rollouts retry web           # retry after a failed analysis
kubectl get rollout -A
kubectl get analysisruns -n <ns> -o yaml
```

## AnalysisTemplate for automated gates

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  metrics:
  - name: success-rate
    interval: 60s
    successCondition: result[0] >= 0.95
    failureCondition: result[0] < 0.95
    provider:
      prometheus:
        address: http://prometheus.monitoring:9090
        query: |
          sum(rate(http_requests_total{status=~"5.."}[1m])) /
          sum(rate(http_requests_total[1m]))
```

How it works: on each canary step the controller creates an `AnalysisRun` from the template, queries the metric provider at `interval`, and aborts if `failureCondition` holds. `pause: {}` (no duration) waits for a manual `promote` - great for human-gated releases.

## ArgoCD + Rollouts together

ArgoCD keeps the Rollout manifest in Git and synced; the Argo Rollouts controller executes the canary steps and traffic shifts in the cluster. ArgoCD detects drift/health, and can display the rollout graph via the plugin.

## Useful checks

```bash
kubectl get applications -n argocd
argocd app sync web --prune
argocd app diff web
kubectl argo rollouts get rollout web
kubectl get replicasets -l app=web
kubectl get analysisruns -n <ns>
```
