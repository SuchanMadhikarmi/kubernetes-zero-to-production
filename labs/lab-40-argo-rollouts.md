---
title: Lab 40 - Progressive Delivery with Argo Rollouts
lesson: 40
module: 12 Production
status: Complete
tags: [lab, argocd, argo-rollouts, progressive-delivery, canary, analysis-template, production]
---

# Lab 40 - Progressive Delivery with Argo Rollouts

## Prerequisites

- Lesson 40 completed.
- A running kind cluster.
- kubectl configured.

## Objective

Deploy an app with a canary strategy, push a good and then a broken update, and observe automatic rollback behavior with Argo Rollouts.

## Step 1 - Install the Argo Rollouts Controller

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

Verify:

```bash
kubectl get pods -n argo-rollouts
```

Expected output (a running controller pod, similar to):

```text
NAME                                READY   STATUS    RESTARTS   AGE
argo-rollouts-xxxxx                 1/1     Running   0          30s
```

## Step 2 - Install the CLI

```bash
curl -sLO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
kubectl argo rollouts version
```

## Step 3 - Create a Canary Rollout

```bash
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app-rollout
spec:
  replicas: 4
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: nginx:alpine
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
EOF
```

## Step 4 - Watch the Initial Rollout

```bash
kubectl argo rollouts get rollout my-app-rollout --watch
```

Expected output: the rollout progresses through steps and ends `Healthy` at weight 100. Ctrl+C to exit.

## Step 5 - A Good Update

```bash
kubectl argo rollouts set image my-app-rollout app=nginx:1.25-alpine
kubectl argo rollouts get rollout my-app-rollout --watch
```

Watch it step 20 -> 40 -> 60 -> 80 -> 100. Ctrl+C.

## Step 6 - A Broken Update and Abort

```bash
kubectl argo rollouts set image my-app-rollout app=nginx:broken-tag-123
```

In a second terminal, abort:

```bash
kubectl argo rollouts abort my-app-rollout
```

## Step 7 - Observations

Check what happened on abort:

```bash
kubectl get replicasets -l app=my-app
kubectl argo rollouts get rollout my-app-rollout
```

Expected behavior:

- The broken Canary ReplicaSet is scaled to 0.
- The Stable ReplicaSet (nginx:1.25-alpine) is scaled back to 4 and serves 100% of traffic.
- Only the small canary percentage ever saw the broken image.

## Cleanup

```bash
kubectl delete rollout my-app-rollout
kubectl delete namespace argo-rollouts
```

[Back to Labs](README.md)
