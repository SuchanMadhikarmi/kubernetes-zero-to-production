---
title: Revision - Packaging and GitOps
module: Modules 09-10
status: Complete
tags: [revision, helm, kustomize, gitops, argocd, packaging]
---

# Revision - Packaging and GitOps

## 1. The Mental Model

Think of Helm as a **factory**, ArgoCD as a **strict building inspector**, and Git as the **single source of truth**.

- The repository has thousands of YAML files that drift apart when you copy and paste them across environments. Helm stops this with **templates** (the blueprint) and **values** (the crayons): one blueprint, colored differently for Dev, Staging, and Prod.
- GitOps inverts the deployment model: instead of a CI tool pushing YAML into the cluster, a controller that **runs inside** the cluster pulls Git state down and reconciles it. Git is the brain; ArgoCD is the hands that reshape the cluster to match the brain.
- Everything hangs on one loop, *desired state vs live state*. Git holds desired state, ArgoCD reads it, diffs against the live cluster, and reconciles any mismatch.

If you remember only three sentences: Helm packages and versions configs, Kustomize patches them without logic, and ArgoCD continuously makes the cluster match Git.

## 2. Core Concepts

### Helm

| Term | Meaning |
|------|---------|
| Chart | A packaged blueprints of Kubernetes objects (Chart.yaml, values.yaml, templates/) |
| Values | Variables injected into templates; override per environment |
| Charts/ | Vendored dependency charts |
| Release | A deployed instance of a Chart, tracked across revisions |
| template engine | Go templates (actions) that turn values + templates into final YAML |
| built-in objects | `.Values`, `.Release.Name`, `.Release.Namespace`, `.Chart`, `.Capabilities` |

Helm 3 is **client-side only**; there is no Tiller server in the cluster. State is stored as a Kubernetes Secret `sh.helm.release.v1.<release>.<revision>` in the release namespace, which is exactly what makes rollbacks work (Helm re-applies a previous revision).

Key render directives: `{{- if ... }}` includes or omits a whole resource; `{{- range $k, $v := .Values.env }}` emits repeated blocks from a list/map; `| quote` wraps a value in quotes; `| toYaml .Values.resources | nindent 10` injects multi-line YAML at the correct indentation; `{{-` and `-}}` trim surrounding whitespace.

### Kustomize

Kustomize does **no templating**. It builds an overlay by patching a `base` with plain YAML. Built into kubectl.

Core elements: `resources`, `patches`, `commonLabels`, `namePrefix`/`nameSuffix`, `images` (for tag replacement), `configMapGenerator`.

### GitOps

| Term | Meaning |
|------|---------|
| GitOps | Git is the single source of truth for cluster state |
| Desired state | The manifests in Git |
| Live state | What is actually running in the cluster |
| Reconciliation | The controller repeatedly brings live state toward desired state |
| Drift | Live state differs from Git (e.g. manual `kubectl edit`) |
| Sync | ArgoCD applying the Git state to the cluster |
| push vs pull | Push (Jenkins) needs kubeconfig to push out; pull (ArgoCD) runs in-cluster |

GitOps principles: declarative desired state in Git, pull-based sync, everything auditable/reversible, drift is a bug. Rollback is `git revert`; ArgoCD reconciles it.

ArgoCD is itself a Kubernetes controller using a **CRD** called `Application` (so `kubectl get applications` works). It natively renders Helm and Kustomize. `syncPolicy.automated.prune: true` deletes resources removed from Git; `selfHeal: true` reverts any manual change back to Git.

### CI vs CD

CI (GitHub Actions) builds and tests code, builds a Docker image, pushes it to a registry, **tags with `${{ github.sha }}`**, then commits the new image tag back into the config repo. CD (ArgoCD) watches that config repo and applies the change. CI never needs kubectl; it only writes to Git.

## 3. Key Commands

### Helm

```bash
helm create mychart                        # scaffold a chart
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo list
helm search repo bitnami
helm install web ./mychart                # create release (revision 1)
helm install web ./mychart -f prod.yaml --set image.tag=v2
helm upgrade web ./mychart --set image.tag=v3   # new revision
helm upgrade --install web ./mychart -f prod.yaml   # create-or-update (CI-friendly)
helm history web                          # all revisions
helm rollback web <revision>              # revert everything at once
helm list -A                              # all releases
helm uninstall web
helm template my-app .                    # render to stdout, no cluster
helm lint .                               # validate chart syntax
helm dependency update ./mychart          # pull Chart.yaml dependencies
helm get values web                       # show merged/effective values
```

### Kustomize

```bash
kubectl kustomize ./overlays/prod        # render to stdout
kubectl apply -k ./overlays/prod         # build + apply
kubectl diff -k ./overlays/prod          # what would change, no apply
```

### ArgoCD

```bash
kubectl get applications -n argocd
kubectl port-forward svc/argocd-server -n argocd 8080:443
argocd app sync web --prune
argocd app diff web
argocd app rollback web <revision>
argocd app list
argocd app delete web
```

## 4. YAML Patterns

### Chart.yaml

```yaml
apiVersion: v2
name: web
description: A web service
type: application
version: 0.1.0          # bump when the chart changes
appVersion: "1.0"      # bump when the app changes
dependencies:
- name: redis
  version: "18.x.x"
  repository: https://charts.bitnami.com/bitnami
```

`version` and `appVersion` are distinct: `version` tracks template logic, `appVersion` tracks the packaged app. `dependencies` lets you pull in sub-charts like redis; run `helm dependency update`.

### values.yaml

```yaml
replicaCount: 2
image:
  repository: nginx
  tag: "1.25"
  pullPolicy: IfNotPresent
ingress:
  enabled: true
resources:
  requests:
    cpu: 100m
    memory: 128Mi
```

Values precedence (highest to lowest): `--set` > `-f/--values` (multiple files, later wins) > chart `values.yaml`.

### A template snippet

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-web
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
      - name: web
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
        env:
        {{- range $k, $v := .Values.env }}
        - name: {{ $k }}
          value: {{ $v | quote }}
        {{- end }}
```

The whole template is the blueprint. `{{ .Release.Name }}` guarantees unique names per release so several releases can coexist. `toYaml ... | nindent 10` injects the resources block at the right indentation. The `range` loop emits one env var per key.

A conditional whole-file guard (e.g. an Ingress that only exists when enabled):

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}-ingress
spec:
  ingressClassName: nginx
{{- end }}
```

This creates the resource only when `ingress.enabled` is true.

### ArgoCD Application

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
    targetRevision: main
    path: apps/web          # folder with YAML or Helm chart/Kustomize dir
  destination:
    server: https://kubernetes.default.svc
    namespace: web
  syncPolicy:
    automated:
      prune: true           # delete resources removed from Git
      selfHeal: true        # revert manual kubectl drift back to Git
    syncOptions:
    - CreateNamespace=true  # create destination namespace if missing
```

- `source` describes `what` to deploy from Git (repo, branch, path).
- `destination` says where in the cluster (server and namespace).
- `syncPolicy.automated` is what makes the whole thing GitOps. `prune` + `selfHeal` together mean the cluster will always end up exactly like Git.

## 5. How It Fits

### GitHub Actions (CI) to ArgoCD (CD)

```text
[ Dev ] --git push--> [ GitHub Repo ]
                          |
                          v
              [ GitHub Actions - CI ]
               1. build Docker image
               2. push to registry (DOCKER_USERNAME/PASSWORD from Secrets)
               3. tag = ${{ github.sha }}
               4. yq update helm/values.yaml image.tag -> git push
                          |
                          v
              [ ArgoCD polls config repo (~3 min) / webhook ]
                          |
                          v
              [ Kubernetes API Server: renders chart, rollout ]
```

- The security split, by design: CI only writes Git and never holds kubeconfig; ArgoCD only reads Git and writes to the cluster. A compromised CI runner can push a bad image but cannot reach the cluster directly.

### Helm lifecycle

| Stage | Command | Helm behavior |
|-------|---------|---------------|
| Install | `helm install` | Creates revision 1, saves Secret v1 |
| Upgrade | `helm upgrade` | Diffs, patches, saves Secret v2 |
| Rollback | `helm rollback` | Re-applies a past revision's saved YAML |
| Uninstall | `helm uninstall` | Deletes resources and Helm Secrets |

Helm and GitOps naturally combine: the chart and `values.yaml` live in the config repo; ArgoCD renders and deploys them, `git revert` becomes the rollback, and Helm's release Secret gives Deployment-level-safe rollbacks when working directly.

## 6. Common Mistakes and Gotchas

| Mistake | Why it happens | How to avoid |
|---------|----------------|--------------|
| Hardcoding values in templates | Forgetting to use `{{ .Values.xxx }}` | Parameterize every runtime value in `values.yaml` |
| Overusing `--set` | quick overrides grow into long CLI calls | use per-env values files stored in Git |
| Blank-line / indentation errors | Missing the `-` in `{{- weekend -}}` | run `helm template` and inspect the rendered output |
| Deleting the Helm release Secret | cleaning up `sh.helm.release.v1.*` | never hand-delete these; rollback depends on them |
| Using `latest` for an image tag | doesn't change in Git | tag with `${{ github.sha }}` |
| Mixing `kubectl apply` with Helm-owned resources | two owners conflict (`managedFields`) | use `helm upgrade --install` for the whole workload |
| Manual `kubectl edit`/`scale` in prod | creates drift | committed to Git or selfHeal reverts it |
| Giving CI kubectl access | easier to reason about | keep CI on Git only; let ArgoCD deploy |
| Auto-prune without PR reviews | deleting YAML in Git deletes from cluster | branch protection + PR review |
| Env-by-hand deployments | `argocd app rollback` misused | Sync is the go-to; rollback is the exception |

## 7. Quick Troubleshooting

- **`helm template` shows wrong indentation / blank lines**: missing trims. Put `{{-` on loop/if openers and `-}}` on closers; use `| nindent`.
- **Pods `ImagePullBackOff` after `helm upgrade`**: bad image tag. `helm history <release>` then `helm rollback <release> <rev>`.
- **`helm upgrade` fails "release not found"**: the release Secret was deleted. `helm list -A` to confirm, then reinstall.
- **Ingress never appears**: the template conditional is `{{/*- if .Values.ingress.enabled }}`; confirm the effective value with `helm get values <release>`.
- **ArgoCD shows OutOfSync but never syncs**: `syncPolicy.automated` is missing; enable it.
- **ArgoCD shows "Degraded"**: app is running but failing (CrashLoopBackOff); `kubectl describe pod`.
- **ArgoCD never detects a commit**: polling default is ~3 minutes; configure a GitHub webhook for instant sync (or verify targetRevision).
- **CI built the image but cluster is stale**: the values bump was never pushed, or the tag was `latest`. Confirm the Git commit and the ArgoCD target branch.

## 8. 30-Second Recap

- **Helm** = Chart (blueprint) + Values (crayons) = Release. Helm 3 is client-side; state lives in Secrets; `helm template` to dry-run, `helm rollback` to undo.
- **Chart** layout: `Chart.yaml` (metadata/appVersion/version/dependencies), `values.yaml`, `templates/` (callable via `{{ .Values }}`, `if`, `range`, `| nindent`), and `charts/`.
- **Kustomize** = overlays patch a base; `kubectl apply -k`; no templating logic.
- **GitOps** = Git is the single source of truth; pull-based; Desired state in Git vs live state (drift) → reconcile.
- **ArgoCD** uses `Application` CRD (repo URL/path/destination), `syncPolicy.automated.sync `prune + selfHeal for drift detection and auto-revert. Other CRDs are `AppProject`, `Repository`, `ApplicationSet`.
- **CI→CD flow**: GitHub Actions builds + pushes image tagged with `${{ github.sha }}`, commits the values bump; ArgoCD sees Git change and deploys. Rollback is `git revert`.

Memory trick: GitHub Actions is the **factory robot** that builds parts and updates the manual; the Docker registry is the **warehouse**; ArgoCD is the **floor manager** that reads the manual and installs the part; the git SHA is the **serial number**.

## Related Lessons

- [Lesson 29 - Helm](../docs/09-packaging/lesson-29-helm.md)
- [Lesson 30 - Helm Deep Dive (Writing Production Charts)](../docs/09-packaging/lesson-30-helm-deep-dive-writing-production-charts.md)
- [Lesson 31 - GitOps Principles and Practices](../docs/10-gitops/lesson-31-gitops-principles-and-practices.md)
- [Lesson 32 - CI/CD Pipelines (GitHub Actions and ArgoCD)](../docs/10-gitops/lesson-32-cicd-pipelines-github-actions-and-argocd.md)

## Related Material

- [Packaging Guide Cheat Sheet](../cheatsheets/packaging-cheatsheet.md)
- [GitOps Cheat Sheet](../cheatsheets/gitops-cheatsheet.md)
- [Interview - GitOps](../interview/gitops.md)

[Back to Revision Index](README.md)