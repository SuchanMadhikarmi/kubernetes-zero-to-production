# Lab 20 - ConfigMaps and Secrets

## Objective

Create a ConfigMap and a Secret. Inject them into a Pod as Environment Variables and Volume mounts. Debug a Pod that fails due to a missing configuration key.

## Prerequisites

- Lesson 23 - ConfigMaps and Secrets.
- A running kind cluster.
- kubectl installed and configured.

### Quick Cluster Setup (kind)

```bash
kind create cluster --name learning
kubectl cluster-info --context kind-learning
```

## Steps

### 1. Create the ConfigMap and Secret

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  LOG_LEVEL: "info"
  MAX_CONNECTIONS: "100"
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
data:
  DB_PASSWORD: c3VwZXJzZWNyZXQ=
EOF
```

### 2. Create the Pod with Environment Variables

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: config-app
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "echo LOG_LEVEL=\$LOG_LEVEL && echo DB_PASSWORD=\$DB_PASSWORD && sleep 3600"]
    env:
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: LOG_LEVEL
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: app-secret
          key: DB_PASSWORD
  restartPolicy: Never
EOF
```

### 3. Verify Environment Variables

```bash
kubectl logs config-app
```

Expected:

```
LOG_LEVEL=info
DB_PASSWORD=supersecret
```

### 4. Test Volume Mount

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    server {
      listen 80;
      server_name localhost;
      location / {
        return 200 "Hello from custom Nginx config!";
      }
    }
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx-custom
spec:
  containers:
  - name: nginx
    image: nginx:1.25-alpine
    ports:
    - containerPort: 80
    volumeMounts:
    - name: nginx-config
      mountPath: /etc/nginx/conf.d/
  volumes:
  - name: nginx-config
    configMap:
      name: nginx-config
EOF
```

```bash
kubectl exec nginx-custom -- curl -s localhost
```

Expected: "Hello from custom Nginx config!"

### 5. Debug a Missing Key

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: config-app-broken
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["sh", "-c", "echo \$LOGGING_LEVEL && sleep 3600"]
    env:
    - name: LOGGING_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: LOGGING_LEVEL
  restartPolicy: Never
EOF
```

```bash
kubectl get pod config-app-broken
kubectl describe pod config-app-broken
```

The Pod fails with `CreateContainerConfigError`.

### 6. Cleanup

```bash
kubectl delete pod config-app nginx-custom config-app-broken
kubectl delete configmap app-config nginx-config
kubectl delete secret app-secret
kind delete cluster --name learning
```

## Verification

- ConfigMap and Secret are created.
- Environment variables are injected correctly.
- Volume mount updates Nginx configuration.
- Missing key causes `CreateContainerConfigError`.

## Expected Output Snapshot

```text
$ kubectl logs config-app
LOG_LEVEL=info
DB_PASSWORD=supersecret

$ kubectl exec nginx-custom -- curl -s localhost
Hello from custom Nginx config!

$ kubectl describe pod config-app-broken
Events:
  Warning  Failed  ... CreateContainerConfigError: ... key "LOGGING_LEVEL" not found in ConfigMap "app-config"
```

## Related

- Lesson file: [lesson-20-configmaps-and-secrets.md](../docs/06-configuration/lesson-20-configmaps-and-secrets.md)
