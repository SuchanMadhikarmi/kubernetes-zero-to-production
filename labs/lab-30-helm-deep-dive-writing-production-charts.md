---
title: Lab 30 - Helm Deep Dive (Writing Production Charts)
lesson: 30
module: 09 Packaging
tags: [kubernetes, helm, charts, templates, values, hooks]
---

# Lab 30 - Helm Deep Dive (Writing Production Charts)

## Objective

Build a full lifecycle of a production-style Helm chart: scaffold it with `helm create`, understand the template structure, add values, validate it with `helm template`, install it, upgrade it, roll it back, and add a pre-install hook example. By the end you will manage a release through the entire Helm lifecycle and see how hooks execute outside the normal render path.

## Prerequisites

- Completion of [Lesson 30 - Helm Deep Dive (Writing Production Charts)](../docs/09-packaging/lesson-30-helm-deep-dive-writing-production-charts.md).
- A running kind (or equivalent) cluster.
- Helm CLI installed.
- kubectl installed and configured.

## Pre-Lab Checklist

Run each command and confirm the expected output before starting.

```bash
helm version
```

Expected output:

```
version.BuildInfo{Version:"v3.x.x", GitCommit:"xxx", GitTreeState:"clean", GoVersion:"go1.x.x"}
```

```bash
kubectl cluster-info
```

Expected output: The cluster control plane URL and CoreDNS section, confirming the cluster is reachable.

---

## Step 1: Scaffold a Chart with `helm create`

```bash
helm create my-api
cd my-api
```

List the generated structure:

```bash
find . -type f -not -path './.helmignore'
```

Expected output: A standard chart tree that includes `Chart.yaml`, `values.yaml`, `values.schema.json`, a `templates/` folder with `_helpers.tpl`, `deployment.yaml`, `service.yaml`, `ingress.yaml`, a `tests/` folder, `NOTES.txt`, and more.

## Step 2: Understand the Template Structure

View the generated chart layout:

```bash
tree .
```

If `tree` is not installed, list templates directly:

```bash
ls -la templates
```

Expected output:

```
total X
drwxrwxr-x ... .
drwxrwxr-x ... ..
drwxrwxr-x ... tests
-rw-rw-r-- ... _helpers.tpl
-rw-rw-r-- ... deployment.yaml
-rw-rw-r-- ... hpa.yaml
-rw-rw-r-- ... ingress.yaml
-rw-rw-r-- ... NOTES.txt
-rw-rw-r-- ... service.yaml
-rw-rw-r-- ... serviceaccount.yaml
```

The default chart is complete but heavy. For this lab, open `templates/_helpers.tpl` and `templates/deployment.yaml`:

```bash
cat templates/_helpers.tpl
```

Expected output: Named sub-templates that build the standard `app.kubernetes.io/*` label set used across all resources. These helpers are the reason every generated resource shares consistent labels, which tooling such as Prometheus and kube-state-metrics rely on.

## Step 3: Add Values to Build a Clean Structure

Simplify the chart to focus on the core concepts. Remove the generated templates you will not use:

```bash
rm templates/hpa.yaml
rm templates/serviceaccount.yaml
rm templates/ingress.yaml
rm -rf templates/tests
rm templates/NOTES.txt
```

Replace `values.yaml` with a clean, staged structure:

```yaml
replicaCount: 2

image:
  repository: nginx
  tag: alpine

service:
  port: 80

ingress:
  enabled: true
  path: /

env:
  LOG_LEVEL: debug
  DB_HOST: postgres-svc
```

Expected result: a `values.yaml` file whose keys (except the `image` tag) exactly match what the templates render. Value names become the contract between `values.yaml` and the templates.

## Step 4: Understand and Rewrite the Templates

Rewrite `templates/deployment.yaml` with a loop over the `env` map:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-api
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
      - name: app
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        ports:
        - containerPort: {{ .Values.service.port }}
        env:
        {{- range $key, $value := .Values.env }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
```

Write `templates/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-svc
spec:
  selector:
    app: {{ .Release.Name }}
  ports:
  - port: {{ .Values.service.port }}
    targetPort: {{ .Values.service.port }}
```

Write how a conditional Ingress would be structured. Create `templates/ingress.yaml`:

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}-ingress
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: {{ .Values.ingress.path }}
        pathType: Prefix
        backend:
          service:
            name: {{ .Release.Name }}-svc
            port:
              number: {{ .Values.service.port }}
{{- end }}
```

Expected result: three template files where the Deployment, Service, and Ingress all derive names and labels from `.Release.Name`, and only the Ingress is guarded by a conditional.

## Step 5: Render with `helm template`

Dry-run the chart without touching the cluster:

```bash
helm template my-release .
```

Expected output: Rendered `deployment.yaml` and `service.yaml` with `nginx:stable` injected, two environment variables emitted by the `range` loop, an Ingress block present, and no Helm comments left in the YAML.

Validate syntax with the linter:

```bash
helm lint .
```

Expected output:

```
1 chart(s) linted, 0 chart(s) failed
```

Test the conditional by disabling the Ingress:

```bash
helm template my-release . --set ingress.enabled=false
```

Expected output: The rendered output contains the Deployment and Service but no Ingress block, proving the `if` guard works.

## Step 6: Install the Chart with `helm install`

```bash
helm install my-api .
```

Expected output:

```
NAME: my-api
LAST DEPLOYED: <timestamp>
NAMESPACE: default
STATUS: deployed
REVISION: 1
```

Verify the release and its resources:

```bash
helm list
kubectl get deployments
kubectl get ingress
```

Expected output: `helm list` shows the `my-api` release with status `deployed`; `kubectl get deployments` shows one deployment; `kubectl get ingress` shows the `my-api-ingress` because `ingress.enabled` defaults to `true`.

## Step 7: Upgrade the Chart with `helm upgrade`

Change the replica count and image tag, then upgrade the running release:

```bash
helm upgrade my-api . --set replicaCount=3 --set image.tag=perl
```

Expected output: revision bumps to `2`, status `deployed`. Check the change:

```bash
helm history my-api
kubectl get deployments
```

Expected output: `helm history` shows Revisions 1 and 2; the Deployment now runs 3 replicas with the Perl image.

## Step 8: Roll Back the Chart with `helm rollback`

Force a broken image to demonstrate a failed upgrade:

```bash
helm upgrade my-api . --set image.tag=broken-tag-123
```

Expected output: The upgrade succeeds from Helm's perspective, but the new pods cannot pull the image:

```bash
kubectl get pods
```

Expected output: pods stuck in `ImagePullBackOff` for the broken tag.

Roll the release back to the last known good revision:

```bash
helm rollback my-api 2
```

Wait for the rollout to complete, then re-check:

```bash
kubectl rollout status deployment/my-api-api
kubectl get pods
```

Expected output: The `broken-tag-123` pods are replaced and the stable Perl pods return to `Running`, restoring the healthy state.

## Step 9: Add a Pre-Install Hook Example

Create `templates/cleanup-job.yaml` that runs before any other resource is installed:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-pre-install-cleanup
  annotations:
    helm.sh/hook: pre-install
    helm.sh/hook-weight: "5"
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: cleanup
        image: busybox:1.36
        command: ["sh", "-c", "echo cleaning stale resources for {{ .Release.Name }}"]
```

Do a dry run to see the hook surfaces separately:

```bash
helm template preinstall-test . --set image.tag=perl
```

Expected output: The Job with the `helm.sh/hook` annotations appears alongside the normal manifests, and it is clearly a `Job` with `restartPolicy: Never`.

Install a new release to trigger the hook:

```bash
helm install preinstall . --set image.tag=perl
```

Expected output: Helm creates the pre-install Job first, waits for it to succeed, then deploys the rest of the resources. Confirm the hook ran:

```bash
kubectl get jobs
kubectl logs -l job-name=preinstall-pre-install-cleanup --tail=5
```

Expected output: a completed Job and the log line `cleanup resources for preinstall`.

---

## Cleanup

Remove the releases and clean up the working directory:

```bash
helm uninstall my-api
helm uninstall preinstall --wait
kubectl get pods
cd ..
```

Expected output: both releases are deleted, their resources are removed, and `kubectl get pods` returns no remaining pods.

---

## What You Learned

- `helm create` scaffolds a complete, ready-to-run chart.
- Templates use built-in objects such as `.Release.Name` and Value-driven conditionals and loops.
- `helm template` renders charts locally for review before anything touches the cluster.
- `helm install`, `helm upgrade`, and `helm rollback` cover the full release lifecycle.
- Helm hooks such as `pre-install` run before the main resources and are the way to attach ordering and clone-up logic.
- `helm uninstall` tears everything down and clears the release state.

## Next Steps

Proceed to [Lesson 43](../docs/14-certifications/lesson-43-cka-exam-masterclass.md) to deepen your operational Kubernetes skills, or review [Lesson 29 - Helm](../docs/09-packaging/lesson-29-helm.md) to reinforce the fundamentals.

---

[Back to Labs](README.md)