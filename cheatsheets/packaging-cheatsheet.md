---
title: Packaging Cheat Sheet (Helm and Kustomize)
topic: packaging
status: Complete
tags: [cheatsheet, helm, kustomize, charts, templating]
---

# Packaging Cheat Sheet (Helm and Kustomize)

Both package Kubernetes manifests. **Helm** uses Go templates + values to produce a release; **Kustomize** is a YAML overlay tool (built into kubectl) with no templating language.

## Helm basics

```bash
helm create mychart                    # scaffold a chart
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo list
helm search repo prometheus-community
helm search hub prometheus             # search public hub
helm install web ./mychart
helm install web ./mychart -f values.yaml
helm install web ./mychart --set image.tag=v2,replicas=5
helm install nginx nginx/stable -n <ns> --create-namespace
helm upgrade web ./mychart --set image.tag=v3
helm history web
helm rollback web <revision>
helm uninstall web
helm get values web
helm get manifest web
helm template ./mychart --values values.yaml > out.yaml   # render, no cluster
helm lint ./mychart
helm list -A
helm status web
helm show values ./mychart
helm show chart ./mychart
```

## Helm chart layout

```text
mychart/
  Chart.yaml          # name, version, appVersion, dependencies
  values.yaml         # default values
  charts/             # bundled dependencies
  templates/          # Go-template manifests
    deployment.yaml
    service.yaml
    _helpers.tpl      # named template helpers
  crds/               # CRDs (installed before templates)
```

Chart.yaml example:

```yaml
apiVersion: v2
name: web
description: A web service
type: application
version: 0.1.0
appVersion: "1.0"
dependencies:
- name: redis
  version: "18.x.x"
  repository: https://charts.bitnami.com/bitnami
```

```bash
helm dependency update ./mychart
```

## Helm template patterns

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-web
  labels:
    app.kubernetes.io/name: web
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
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
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
```

values.yaml:

```yaml
replicaCount: 2
image:
  repository: nginx
  tag: "1.25"
  pullPolicy: IfNotPresent
resources:
  requests:
    cpu: 100m
    memory: 128Mi
```

Common template functions: `default`, `quote`, `toYaml`, `nindent`, `include`, `if/else`, `range`, `with`, `{{-` trim markers, `printf`, `trunc`, `upper`.

Values precedence (highest to lowest): `--set`/`--set-file` > `-f/--values` (later wins) > chart `values.yaml`.

## Kustomize basics

```bash
kubectl kustomize ./overlays/prod > out.yaml    # render to stdout
kubectl apply -k ./overlays/prod                # build and apply
```

Layout:

```text
base/
  kustomization.yaml
  deployment.yaml
  service.yaml
overlays/
  prod/
    kustomization.yaml      # patches + namePrefix/suffix + commonLabels
  dev/
    kustomization.yaml
```

Base kustomization:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
commonLabels:
  app: web
namePrefix: prod-
```

Overlay patch:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
patches:
- path: increase-replicas.yaml
nameSuffix: -prod
commonLabels:
  env: prod
images:
- name: nginx
  newTag: "1.26"
```

`kubectl diff -k ./overlays/prod` checks differences without applying.

## Helm vs Kustomize quick decision

| Need | Prefer |
|------|--------|
| Install third-party software (Prometheus, Redis, ArgoCD) | Helm |
| Parameterize with values, upgrade/rollback, history | Helm |
| Simple patches across dev/prod, no learning curve | Kustomize |
| GitOps with plain overlays (ArgoCD native) | Kustomize |
| Enterprise package management, releases | Helm + chart repo |

Many teams use both: Helm to install the stack, Kustomize for small environment-specific patches.

## Production notes

- Pin chart versions and appVersions; never install `latest`.
- Separate values files per environment: `values-dev.yaml`, `values-prod.yaml` (never commit secrets).
- `helm template` renders without a cluster - always use it in CI.
- Chart `version` bumps when the chart changes; `appVersion` when the app changes.
- For secrets in Helm, use Sealed Secrets / external-secrets rather than plain values.
