# Lab 33 - Helm

## Prerequisite

- Completion of [Lesson 33 - Helm](../docs/09-packaging/lesson-33-helm.md).
- A running kind cluster.
- kubectl installed and configured.

## Objective

Install Helm, create a basic chart, deploy it, and then perform a rollback. Understand the difference between raw YAML and Helm-managed deployments.

## Estimated Time

20 minutes.

---

## Step 1: Install Helm CLI

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm version
```

Expected output:

```
version.BuildInfo{Version:"v3.x.x", GitCommit:"xxx", GitTreeState:"clean", GoVersion:"go1.x.x"}
```

## Step 2: Generate a Basic Helm Chart

```bash
helm create my-app
cd my-app
```

## Step 3: Simplify the Templates

```bash
rm templates/*.yaml templates/*.tpl
rm -rf templates/tests
rm templates/NOTES.txt
```

## Step 4: Write Your Own Template

Create `templates/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-deployment
  labels:
    app: {{ .Values.appName }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Values.appName }}
  template:
    metadata:
      labels:
        app: {{ .Values.appName }}
    spec:
      containers:
      - name: {{ .Values.appName }}
        image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
        ports:
        - containerPort: 80
```

## Step 5: Write Your Own Values File

```yaml
appName: my-nginx
replicaCount: 2

image:
  repository: nginx
  tag: alpine
```

## Step 6: Test the Rendering (Dry Run)

```bash
helm template my-web .
```

Expected output: A perfectly formed Deployment YAML with your values injected.

## Step 7: Install Your Custom Chart

```bash
helm install my-web .
```

Verify it worked:

```bash
kubectl get deployments
```

Expected output: A deployment named `my-web-deployment` with 2 replicas.

## Step 8: Simulate a Bad Upgrade

```bash
helm upgrade my-web . --set image.tag=broken-tag-123
```

Check the pods:

```bash
kubectl get pods
```

Expected output: A new Pod trying to start, but failing with `ImagePullBackOff`.

## Step 9: Rollback

```bash
helm history my-web
helm rollback my-web 1
```

Check the pods again:

```bash
kubectl get pods
```

Expected output: The broken pod is gone, and the healthy alpine pods are running.

## Step 10: Cleanup

```bash
helm uninstall my-web
cd ..
```

---

## What You Learned

- Helm is the package manager for Kubernetes.
- A Chart is a package containing templates and default values.
- Values are injected into templates to generate the final YAML.
- Helm stores release history as Secrets in the namespace.
- `helm rollback` instantly reverts a failed deployment.

## Next Steps

Proceed to [Lesson 34 - Kustomize](../docs/09-packaging/lesson-39-helm-deep-dive-writing-production-charts.md) to learn about the Kubernetes-native alternative to Helm.

---

[Back to Labs](README.md)
